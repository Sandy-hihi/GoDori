import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/widgets/home/home_theme.dart';

/// 게임도구 '팀 나누기' (126차) — 손가락으로 팀 나누기
///   - 모두 화면에 손가락을 꾹 대고 있으면 손가락마다 원이 생기고, 2초 동안 그대로면 팀이 정해짐
///     → 같은 팀끼리 같은 색 원(+ 퍼지는 물결, 같은 팀끼리 옅은 선), 진동(되는 기기만)
///   - 팀은 고르게(인원 차이 최대 1명). 손가락이 늘거나 줄면 2초를 다시 셈
///   - 손가락을 떼도 결과 원은 남음 → 다시 하려면 화면을 다시 누름
///   - PC 마우스(실행.bat으로 볼 때): 누른 곳에 점이 고정됨(다시 누르면 지움) — 손가락 여러 개 대신
///   - 127차 pickOne(선 뽑기) → 128차: 2초 그대로면 한 손가락 원에만 색이 차오름 + 파동 한 번 + 둘레 잔상 (번쩍이는 불빛 돌기는 뺌)
class FingerTeamPicker extends StatefulWidget {
  final List<Color> colors;
  final bool pickOne;
  const FingerTeamPicker({super.key, required this.colors, this.pickOne = false});

  @override
  State<FingerTeamPicker> createState() => _FingerTeamPickerState();
}

class _FingerTeamPickerState extends State<FingerTeamPicker> with TickerProviderStateMixin {
  static const _holdMs = 2000;
  static const _radius = 54.0;

  final _rand = Random();
  final Map<int, Offset> _fingers = {}; // 손가락(포인터) → 자리 (마우스 고정 점은 음수 번호)
  final Map<int, int> _team = {}; // 정해진 팀 (0부터)
  final Map<int, Offset> _left = {}; // 정해진 뒤 뗀 손가락 자리 (결과로 남김)
  int _teamCount = 2;
  bool _decided = false;
  int _mouseSeq = -1;
  int? _winner; // 선 뽑기: 뽑힌 손가락

  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(milliseconds: _holdMs))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _decide();
    });
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  int get _need => widget.pickOne ? 2 : max(2, _teamCount);

  @override
  void dispose() {
    _pulse.dispose();
    _hold.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _reset() {
    _team.clear();
    _left.clear();
    _decided = false;
    _burst.reset();
    _winner = null;
  }

  void _restartHold() {
    _hold.stop();
    if (!_decided && _fingers.length >= _need) {
      _hold.forward(from: 0);
    } else {
      _hold.reset();
    }
  }

  void _decide() {
    if (_decided || _fingers.length < _need) return;
    final ids = _fingers.keys.toList()..shuffle(_rand);
    if (widget.pickOne) {
      // 선 뽑기: 한 손가락만 골라 색을 채움 (128차)
      setState(() {
        _winner = ids[_rand.nextInt(ids.length)];
        _decided = true;
      });
      _burst.forward(from: 0);
      HapticFeedback.heavyImpact();
      return;
    }
    // 팀 번호도 섞어서 '1팀'이 늘 한 명 더 많지 않게
    final order = List.generate(_teamCount, (i) => i)..shuffle(_rand);
    setState(() {
      for (var i = 0; i < ids.length; i++) {
        _team[ids[i]] = order[i % _teamCount];
      }
      _decided = true;
    });
    _burst.forward(from: 0);
    HapticFeedback.heavyImpact();
  }

  void _down(PointerDownEvent e) {
    setState(() {
      if (_decided && _fingers.isEmpty) _reset(); // 결과를 보고 다시 누르면 새로
      if (_decided) return; // 정해진 뒤 새로 댄 손가락은 무시
      if (e.kind == PointerDeviceKind.mouse) {
        // PC: 누른 곳에 점 고정, 점을 다시 누르면 지움
        final hit = _fingers.entries.where((f) => f.key < 0 && (f.value - e.localPosition).distance < _radius);
        if (hit.isNotEmpty) {
          _fingers.remove(hit.first.key);
        } else {
          _fingers[_mouseSeq--] = e.localPosition;
        }
      } else {
        _fingers[e.pointer] = e.localPosition;
      }
    });
    _restartHold();
  }

  void _move(PointerMoveEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    setState(() => _fingers[e.pointer] = e.localPosition);
  }

  void _up(PointerEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    setState(() {
      final pos = _fingers.remove(e.pointer)!;
      if (_decided) _left[e.pointer] = pos;
    });
    if (!_decided) _restartHold();
  }

  void _setTeams(int n) {
    setState(() {
      _teamCount = n;
      if (_decided) {
        _reset();
        _fingers.removeWhere((k, _) => k < 0);
      }
    });
    _restartHold();
  }

  Color _colorOf(int team) => widget.colors[team % widget.colors.length];

  @override
  Widget build(BuildContext context) {
    final points = {..._left, ..._fingers};
    final counts = List.filled(_teamCount, 0);
    for (final id in points.keys) {
      final t = _team[id];
      if (t != null && t < _teamCount) counts[t]++;
    }
    final pick = widget.pickOne;
    final String hint;
    if (_decided) {
      hint = pick
          ? (_fingers.isEmpty ? '선이 정해졌어요! 다시 하려면 화면을 눌러 주세요' : '선이 정해졌어요!')
          : (_fingers.isEmpty ? '팀이 나뉘었어요! 다시 하려면 화면을 눌러 주세요' : '팀이 나뉘었어요!');
    } else if (_fingers.isEmpty) {
      hint = '';
    } else if (_fingers.length < _need) {
      hint = pick ? '손가락이 2개 이상 필요해요' : '팀 수보다 많은 손가락이 필요해요';
    } else {
      hint = '그대로 기다려 주세요';
    }
    return Column(
      children: [
        // 위: 팀 수 · 결과 (선 뽑기는 없음)
        if (!pick) Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Row(
            children: [
              const GuestText('팀 수', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              for (var n = 2; n <= 6; n++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$n', style: TextStyle(fontWeight: FontWeight.bold, color: _teamCount == n ? Colors.white : kInk)),
                    selected: _teamCount == n,
                    selectedColor: kInk,
                    showCheckmark: false,
                    onSelected: (_) => _setTeams(n),
                  ),
                ),
              const Spacer(),
              if (_decided)
                Wrap(
                  spacing: 8,
                  children: [
                    for (var t = 0; t < _teamCount; t++)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: _colorOf(t), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          GuestText('${t + 1}팀', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          GuestText('${counts[t]}명', style: const TextStyle(color: Colors.white70)),
                        ]),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (!pick) const Divider(height: 1),
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (points.isEmpty)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app, size: 88, color: Color(0xFFCFC6B8)),
                        const SizedBox(height: 16),
                        const GuestText('모두 손가락을 화면에 꾹 대 주세요',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kInk)),
                        const SizedBox(height: 8),
                        GuestText(pick ? '2초 동안 그대로 있으면 한 명에게 불빛이 들어와요' : '2초 동안 그대로 있으면 같은 팀끼리 같은 색으로 나뉘어요',
                            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: kMuted)),
                      ],
                    ),
                  ),
                AnimatedBuilder(
                  animation: Listenable.merge([_pulse, _hold, _burst]),
                  builder: (context, _) => CustomPaint(
                    painter: _FingerPainter(
                      points: points,
                      team: _team,
                      colorOf: _colorOf,
                      decided: _decided,
                      pulse: _pulse.value,
                      hold: _hold.value,
                      burst: _burst.value,
                      radius: _radius,
                      pickOne: pick,
                      litId: _winner,
                    ),
                  ),
                ),
                if (hint.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 20,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: kInk.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: GuestText(hint, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
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
}

class _FingerPainter extends CustomPainter {
  final Map<int, Offset> points;
  final Map<int, int> team;
  final Color Function(int) colorOf;
  final bool decided;
  final double pulse, hold, burst, radius;
  final bool pickOne;
  final int? litId;

  _FingerPainter({
    this.pickOne = false,
    this.litId,
    required this.points,
    required this.team,
    required this.colorOf,
    required this.decided,
    required this.pulse,
    required this.hold,
    required this.burst,
    required this.radius,
  });

  // 128차 선 뽑기: 다른 손가락은 기다릴 때 그대로(회색 원), 뽑힌 손가락 원만 가운데부터 색이 차오름
  //   + 파동 한 번 퍼짐 + 둘레에 옅은 잔상 고리 두 개가 남음
  void _paintPick(Canvas canvas) {
    for (final e in points.entries) {
      if (e.key == litId) continue;
      final r = radius + pulse * 4;
      canvas.drawCircle(e.value, r, Paint()..color = kInk.withValues(alpha: 0.08));
      canvas.drawCircle(
        e.value,
        r,
        Paint()
          ..color = kInk.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    final c = litId == null ? null : points[litId];
    if (c == null) return;
    final r = radius + pulse * 4;
    final fill = Curves.easeOutCubic.transform((burst * 1.8).clamp(0.0, 1.0)); // 앞쪽 절반쯤에 다 참
    final show = Curves.easeOut.transform((burst * 2).clamp(0.0, 1.0));
    // 둘레 잔상 (나타난 뒤 남음)
    for (final (gap, a) in [(16.0, 0.22), (34.0, 0.1)]) {
      canvas.drawCircle(
        c,
        r + gap,
        Paint()
          ..color = kOrange.withValues(alpha: a * show)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    // 파동 한 번
    canvas.drawCircle(
      c,
      r + Curves.easeOut.transform(burst) * radius * 2.4,
      Paint()
        ..color = kOrange.withValues(alpha: 0.4 * (1 - burst))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    // 원 (기다릴 때와 같은 회색 바탕 위에 주황이 차오름)
    canvas.drawCircle(c, r, Paint()..color = kInk.withValues(alpha: 0.08));
    canvas.drawCircle(c, r * fill, Paint()..color = kOrange);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = kOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (pickOne && decided) {
      _paintPick(canvas);
      return;
    }
    if (decided) {
      // 같은 팀끼리 옅은 선 (물결과 함께 나타남)
      final byTeam = <int, List<Offset>>{};
      for (final e in points.entries) {
        final t = team[e.key];
        if (t != null) byTeam.putIfAbsent(t, () => []).add(e.value);
      }
      for (final e in byTeam.entries) {
        final line = Paint()
          ..color = colorOf(e.key).withValues(alpha: 0.28 * burst)
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round;
        final ps = e.value;
        for (var i = 0; i + 1 < ps.length; i++) {
          canvas.drawLine(ps[i], Offset.lerp(ps[i], ps[i + 1], Curves.easeOut.transform(burst))!, line);
        }
      }
    }
    for (final e in points.entries) {
      final c = e.value;
      final t = team[e.key];
      if (decided && t != null) {
        final color = colorOf(t);
        // 퍼지는 물결
        final wave = Curves.easeOut.transform(burst);
        canvas.drawCircle(
          c,
          radius + wave * radius * 2.2,
          Paint()..color = color.withValues(alpha: 0.35 * (1 - burst)),
        );
        // 팀 색 원 (톡 커졌다 자리 잡음)
        final pop = 1 + 0.25 * sin(min(1.0, burst * 1.6) * pi);
        canvas.drawCircle(c, radius * pop + pulse * 4, Paint()..color = color);
        canvas.drawCircle(
          c,
          radius * pop + pulse * 4 + 6,
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '${t + 1}',
            style: TextStyle(color: Colors.white, fontSize: radius * 0.8, fontWeight: FontWeight.w800),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      } else {
        // 아직: 회색 원 + 2초 세는 주황 테두리
        final r = radius + pulse * 6;
        canvas.drawCircle(c, r, Paint()..color = kInk.withValues(alpha: 0.10));
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = kInk.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        if (hold > 0) {
          canvas.drawArc(
            Rect.fromCircle(center: c, radius: r + 8),
            -pi / 2,
            2 * pi * hold,
            false,
            Paint()
              ..color = kOrange
              ..style = PaintingStyle.stroke
              ..strokeWidth = 7
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FingerPainter old) => true;
}
