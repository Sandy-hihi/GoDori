import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/widgets/home/home_theme.dart';

/// 게임도구 '주사위' (126차) — 진짜 굴러가는 것처럼
///   - 굴리면 1.2초 동안 주사위가 위아래로 튀면서(점점 낮게) 세 방향으로 돌고, 눈이 빠르게 바뀌다가 점점 느려져 멈춤
///   - 바닥 그림자가 주사위 높이에 따라 커졌다 작아짐, 멈출 때 진동(되는 기기만)
///   - 주사위 1~3개 (2개 이상이면 합계), 주사위를 눌러도 굴러감
///   - 눈은 숫자 대신 점(1~6)
class DiceRoller extends StatefulWidget {
  const DiceRoller({super.key});

  @override
  State<DiceRoller> createState() => _DiceRollerState();
}

class _DiceRollerState extends State<DiceRoller> with SingleTickerProviderStateMixin {
  static const _maxDice = 3;
  final _rand = Random();
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..addListener(_onTick)
    ..addStatusListener(_onStatus);

  int _count = 1;
  List<int> _final = [1, 1, 1];
  List<int> _shown = [1, 1, 1];
  // 주사위마다 도는 양(바퀴 수)·방향·튀는 위상 — 굴릴 때마다 새로
  List<List<double>> _spin = List.generate(_maxDice, (_) => [0, 0, 0]);
  List<double> _phase = List.filled(_maxDice, 0);
  int _lastStep = -1;
  bool _landed = true;

  bool get _rolling => _c.isAnimating;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _roll() {
    if (_rolling) return;
    _final = List.generate(_maxDice, (_) => _rand.nextInt(6) + 1);
    _spin = List.generate(_maxDice, (_) {
      double turns(double min, double max) => (min + _rand.nextDouble() * (max - min)) * (_rand.nextBool() ? 1 : -1);
      return [turns(1.5, 3), turns(1.5, 3), turns(0.5, 1.5)];
    });
    _phase = List.generate(_maxDice, (_) => _rand.nextDouble() * 0.25);
    _lastStep = -1;
    _landed = false;
    HapticFeedback.selectionClick();
    _c.forward(from: 0);
  }

  // 눈이 바뀌는 때: 처음엔 빠르게, 끝으로 갈수록 느리게 (t^0.55 눈금)
  void _onTick() {
    final t = _c.value;
    if (t >= 0.86) {
      if (!_landed) {
        _landed = true;
        setState(() => _shown = List.of(_final));
      }
      return;
    }
    final step = (pow(t, 0.55) * 16).floor();
    if (step != _lastStep) {
      _lastStep = step;
      setState(() {
        _shown = [
          for (var i = 0; i < _maxDice; i++)
            () {
              var v = _rand.nextInt(6) + 1;
              if (v == _shown[i]) v = v % 6 + 1; // 같은 눈이 연달아 나오지 않게
              return v;
            }(),
        ];
      });
    }
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) {
      setState(() => _shown = List.of(_final));
      HapticFeedback.mediumImpact();
    }
  }

  Widget _die(int i, double size) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _rolling ? (_c.value - _phase[i] * (1 - _c.value)).clamp(0.0, 1.0) : 1.0;
        final left = 1 - Curves.easeOutCubic.transform(t); // 남은 회전 (1 → 0)
        // 튀기: 세 번, 점점 낮게
        final hop = (sin(t * pi * 3)).abs() * pow(1 - t, 1.4) * size * 0.55;
        final spin = _spin[i];
        final m = Matrix4.identity()..setEntry(3, 2, 0.0016);
        m.multiply(Matrix4.translationValues(0, -hop, 0));
        m.multiply(Matrix4.rotationX(spin[0] * 2 * pi * left));
        m.multiply(Matrix4.rotationY(spin[1] * 2 * pi * left));
        m.multiply(Matrix4.rotationZ(spin[2] * 2 * pi * left));
        final s = 1 + 0.12 * sin(t * pi) * (1 - t);
        m.multiply(Matrix4.diagonal3Values(s, s, 1));
        final lift = (hop / (size * 0.55)).clamp(0.0, 1.0);
        return SizedBox(
          width: size * 1.15,
          height: size * 1.9,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // 바닥 그림자 — 높이 뜨면 작고 흐리게
              Positioned(
                bottom: size * 0.08,
                child: Container(
                  width: size * (0.85 - 0.35 * lift),
                  height: size * 0.12,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16 - 0.1 * lift),
                    borderRadius: BorderRadius.circular(size),
                  ),
                ),
              ),
              Positioned(
                bottom: size * 0.14,
                child: Transform(
                  alignment: Alignment.center,
                  transform: m,
                  child: _DieFace(value: _shown[i], size: size),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sum = _final.take(_count).fold<int>(0, (a, b) => a + b);
    return LayoutBuilder(builder: (context, box) {
      final size = min(200.0, min(box.maxWidth / (_count * 1.4 + 0.4), box.maxHeight * 0.32));
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 주사위 개수
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GuestText('주사위 개수', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kMuted)),
                const SizedBox(width: 12),
                for (var n = 1; n <= _maxDice; n++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text('$n', style: TextStyle(fontWeight: FontWeight.bold, color: _count == n ? Colors.white : kInk)),
                      selected: _count == n,
                      selectedColor: kInk,
                      showCheckmark: false,
                      onSelected: _rolling ? null : (_) => setState(() => _count = n),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _roll,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (var i = 0; i < _count; i++) _die(i, size)],
              ),
            ),
            // 합계 (2개 이상)
            SizedBox(
              height: 40,
              child: _count > 1 && !_rolling
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const GuestText('합계', style: TextStyle(fontSize: 20, color: kMuted, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        Text('$sum', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kInk)),
                      ],
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _rolling ? 0.5 : 1,
              child: ElevatedButton(
                onPressed: _rolling ? null : _roll,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  backgroundColor: kOrange,
                  disabledBackgroundColor: kOrange,
                ),
                child: const GuestText('주사위 굴리기',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// 주사위 한 면 (점 1~6)
class _DieFace extends StatelessWidget {
  final int value;
  final double size;
  const _DieFace({required this.value, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF1ECE4)],
        ),
        borderRadius: BorderRadius.circular(size * 0.2),
        border: Border.all(color: const Color(0xFFE3DCD0), width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: CustomPaint(painter: _PipPainter(value)),
    );
  }
}

class _PipPainter extends CustomPainter {
  final int value;
  _PipPainter(this.value);

  // 3×3 칸 중 점 자리 (0~8: 왼쪽 위부터)
  static const _layout = {
    1: [4],
    2: [2, 6],
    3: [2, 4, 6],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * (value == 1 ? 0.11 : 0.085);
    final paint = Paint()..color = value == 1 ? const Color(0xFFD9381E) : kInk;
    for (final k in _layout[value] ?? const <int>[]) {
      final cx = size.width * (0.25 + 0.25 * (k % 3));
      final cy = size.height * (0.25 + 0.25 * (k ~/ 3));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipPainter old) => old.value != value;
}
