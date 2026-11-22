import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_idle_home.dart';

/// 게임도구 타이머 화면 조각 (131차 — 23:37 채팅 시안 그대로)
///   - CountdownRing: 남은 시간만큼 줄어드는 원형 띠(1초마다 부드럽게), 마지막 10초는 빨강 + 숫자 두근
///   - ToolRoundButton: 둥근 버튼 + 아래 글자 (지우기·처음부터·시작…)
///   - TimeChip: '+30초' 같은 둥근 칩
///   - StopwatchView: 초침이 도는 다이얼 + 가운데 1/100초, 랩 카드(가장 빠름 초록·가장 느림 빨강)

const _red = Color(0xFFE24B4A);
const _redDark = Color(0xFFA32D2D);
const _track = Color(0xFFEFE9DF);

String formatMmSs(int seconds) {
  final m = seconds ~/ 60, s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String formatSw(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
  return '$m:$s.$cs';
}

const _tabular = [FontFeature.tabularFigures()];

/// 둥근 버튼 + 아래 글자
class ToolRoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final Color color;
  const ToolRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.color = kOrange,
  });

  @override
  Widget build(BuildContext context) {
    final d = primary ? 84.0 : 64.0;
    final on = onTap != null;
    return Opacity(
      opacity: on ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: primary ? color : _track,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: d,
                height: d,
                child: Icon(icon, size: primary ? 40 : 28, color: primary ? Colors.white : kMuted),
              ),
            ),
          ),
          const SizedBox(height: 8),
          GuestText(label, style: const TextStyle(fontSize: 14, color: kMuted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// '+30초' 같은 둥근 칩 (outlined = '직접 입력'처럼 테두리만)
class TimeChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool outlined;
  const TimeChip({super.key, required this.label, required this.onTap, this.icon, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: outlined ? Colors.white : kBg,
        shape: StadiumBorder(side: outlined ? const BorderSide(color: Color(0xFFD9D1C4)) : BorderSide.none),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: kInk), const SizedBox(width: 6)],
              GuestText(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 카운트다운 원형 띠 + 가운데 시간
class CountdownRing extends StatelessWidget {
  final int remaining;
  final int total;
  final bool running;
  final bool finished;
  final double size;
  const CountdownRing({
    super.key,
    required this.remaining,
    required this.total,
    required this.running,
    required this.finished,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final frac = total <= 0 ? 0.0 : (remaining / total).clamp(0.0, 1.0);
    final last10 = total > 0 && remaining > 0 && remaining <= 10;
    final color = finished || last10 ? _red : kOrange;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: frac),
        // 1초마다 남은 시간이 줄 때 띠가 1초 동안 이어서 줄어듦 (시간을 더하거나 처음부터면 빠르게)
        duration: Duration(milliseconds: running ? 1000 : 300),
        curve: running ? Curves.linear : Curves.easeOut,
        builder: (context, f, child) => CustomPaint(
          painter: _RingPainter(fraction: f, color: color, stroke: size * 0.065),
          child: child,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 마지막 10초: 1초마다 숫자가 살짝 커졌다 돌아옴
              TweenAnimationBuilder<double>(
                key: ValueKey(last10 && running ? remaining : -1),
                tween: Tween(begin: last10 && running ? 1.1 : 1.0, end: 1.0),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                builder: (context, k, child) => Transform.scale(scale: k, child: child),
                child: Text(
                  formatMmSs(remaining),
                  style: TextStyle(
                    fontSize: size * 0.21,
                    fontWeight: FontWeight.w800,
                    color: finished || last10 ? _redDark : kInk,
                    fontFeatures: _tabular,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              if (finished)
                GuestText('⏰ 시간 종료!', style: TextStyle(fontSize: size * 0.06, color: _redDark, fontWeight: FontWeight.bold))
              else if (total <= 0)
                GuestText('시간을 정해 주세요', style: TextStyle(fontSize: size * 0.05, color: kMuted))
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  GuestText('설정 시간', style: TextStyle(fontSize: size * 0.05, color: kMuted)),
                  const SizedBox(width: 6),
                  Text(formatMmSs(total), style: TextStyle(fontSize: size * 0.05, color: kMuted, fontFeatures: _tabular)),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final double stroke;
  _RingPainter({required this.fraction, required this.color, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke / 2 - 2;
    canvas.drawCircle(c, r, Paint()
      ..color = _track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    if (fraction <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -pi / 2,
      2 * pi * fraction,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.fraction != fraction || o.color != color || o.stroke != stroke;
}

/// 스탑워치 (초침 다이얼 + 랩 카드)
class StopwatchView extends StatefulWidget {
  const StopwatchView({super.key});

  @override
  State<StopwatchView> createState() => _StopwatchViewState();
}

class _StopwatchViewState extends State<StopwatchView> {
  final Stopwatch _sw = Stopwatch();
  Timer? _tick;
  final List<Duration> _laps = []; // 누른 때의 전체 시간 (오래된 것부터)

  bool get _running => _sw.isRunning;

  void _start() {
    _sw.start();
    PadIdleHome.hold(this); // 140차: 스톱워치가 도는 동안엔 30분 자동 홈으로 가지 않음
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 30), (_) => setState(() {}));
    setState(() {});
  }

  void _pause() {
    _sw.stop();
    PadIdleHome.release(this);
    _tick?.cancel();
    setState(() {});
  }

  void _reset() {
    _sw
      ..stop()
      ..reset();
    PadIdleHome.release(this);
    _tick?.cancel();
    setState(_laps.clear);
  }

  void _lap() => setState(() => _laps.add(_sw.elapsed));

  @override
  void dispose() {
    _tick?.cancel();
    _sw.stop();
    PadIdleHome.release(this);
    super.dispose();
  }

  Widget _lapPanel() {
    final splits = [for (var i = 0; i < _laps.length; i++) _laps[i] - (i == 0 ? Duration.zero : _laps[i - 1])];
    int? fast, slow;
    if (splits.length >= 2) {
      var f = 0, w = 0;
      for (var i = 1; i < splits.length; i++) {
        if (splits[i] < splits[f]) f = i;
        if (splits[i] > splits[w]) w = i;
      }
      fast = f;
      slow = w;
    }
    return Container(
      width: 300,
      margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: GuestText('랩 기록 (${_laps.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kInk)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: splits.length,
              itemBuilder: (context, k) {
                final i = splits.length - 1 - k; // 최근 것 위
                final isFast = i == fast, isSlow = i == slow;
                final bg = isFast ? const Color(0xFFEAF3DE) : (isSlow ? const Color(0xFFFCEBEB) : Colors.white);
                final fg = isFast ? const Color(0xFF27500A) : (isSlow ? const Color(0xFF791F1F) : kInk);
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: fg.withValues(alpha: 0.12),
                      child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(formatSw(splits[i]),
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: fg, fontFeatures: _tabular)),
                        if (isFast || isSlow)
                          GuestText(isFast ? '가장 빠름' : '가장 느림', style: TextStyle(fontSize: 12, color: fg)),
                      ]),
                    ),
                    Text(formatSw(_laps[i]), style: const TextStyle(fontSize: 12, color: kMuted, fontFeatures: _tabular)),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _sw.elapsed;
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final size = min(320.0, min(box.maxWidth * 0.7, box.maxHeight - 170));
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: size,
                    height: size,
                    child: CustomPaint(
                      painter: _DialPainter(seconds: e.inMilliseconds / 1000.0),
                      child: Align(
                        alignment: const Alignment(0, 0.42),
                        child: Text(formatSw(e),
                            style: TextStyle(fontSize: size * 0.11, fontWeight: FontWeight.w800, color: kInk, fontFeatures: _tabular)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ToolRoundButton(icon: Icons.replay, label: '처음부터', onTap: e > Duration.zero ? _reset : null),
                      const SizedBox(width: 28),
                      ToolRoundButton(
                        icon: _running ? Icons.pause : Icons.play_arrow,
                        label: _running ? '멈춤' : '시작',
                        onTap: _running ? _pause : _start,
                        primary: true,
                        color: kInk,
                      ),
                      const SizedBox(width: 28),
                      ToolRoundButton(icon: Icons.flag, label: '랩', onTap: _running ? _lap : null),
                    ],
                  ),
                ],
              ),
            );
          }),
        ),
        if (_laps.isNotEmpty) _lapPanel(),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  final double seconds;
  _DialPainter({required this.seconds});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    canvas.drawCircle(c, r, Paint()
      ..color = _track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    for (var i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      final a = i * 6 * pi / 180;
      final dir = Offset(sin(a), -cos(a));
      canvas.drawLine(
        c + dir * r,
        c + dir * (r - (major ? r * 0.09 : r * 0.045)),
        Paint()
          ..color = major ? const Color(0xFFB9AFA0) : const Color(0xFFDDD5C9)
          ..strokeWidth = major ? 3 : 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
    // 지나간 초만큼 옅은 주황 띠
    final sec = seconds % 60;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.8),
      -pi / 2,
      2 * pi * sec / 60,
      false,
      Paint()
        ..color = kOrange.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.1,
    );
    // 초침
    final a = sec * 6 * pi / 180;
    final dir = Offset(sin(a), -cos(a));
    canvas.drawLine(c - dir * r * 0.12, c + dir * r * 0.86, Paint()
      ..color = kOrange
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, r * 0.045, Paint()..color = kOrange);
  }

  @override
  bool shouldRepaint(covariant _DialPainter o) => o.seconds != seconds;
}
