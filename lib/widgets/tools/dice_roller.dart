import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/widgets/home/home_theme.dart';

/// 게임도구 '주사위' (126차, 127차 입체 정육면체)
///   - 면 6개로 만든 정육면체(마주 보는 면의 합 7). 늘 살짝 기울여 앞·위·옆 세 면이 보임
///   - 굴리면 1.4초 동안 세 번 튀면서(점점 낮게) 세 방향으로 여러 바퀴 구르다 나온 눈이 앞면으로 오며 멈춤
///     (지금 자리에서 이어서 굴러감 — 끊기지 않음), 면마다 빛을 받는 정도로 밝기 다르게, 바닥 그림자, 멈출 때 진동
///   - 주사위 1~3개(2개 이상이면 합계), 주사위를 눌러도 굴러감. 눈은 모두 검정(127차)
///   - 보이는 면만 그림: 회전시킨 면의 바깥 방향이 화면 쪽인 면만 (볼록한 정육면체라 순서 걱정 없음)
class DiceRoller extends StatefulWidget {
  const DiceRoller({super.key});

  @override
  State<DiceRoller> createState() => _DiceRollerState();
}

/// 3차원 점·방향 (Matrix4 회전과 같은 규칙으로 직접 돌림 — vector_math를 따로 쓰지 않으려고)
typedef _V = ({double x, double y, double z});

_V _rotX(_V v, double a) => (x: v.x, y: cos(a) * v.y - sin(a) * v.z, z: sin(a) * v.y + cos(a) * v.z);
_V _rotY(_V v, double a) => (x: cos(a) * v.x + sin(a) * v.z, y: v.y, z: -sin(a) * v.x + cos(a) * v.z);
_V _rotZ(_V v, double a) => (x: cos(a) * v.x - sin(a) * v.y, y: sin(a) * v.x + cos(a) * v.y, z: v.z);

/// 면: 눈 · 앞면(화면 쪽 = -z)에서 그 자리로 돌리는 각도(X, Y)
/// 화면 좌표: x 오른쪽, y 아래, z 화면 안쪽(멀어짐)
const _faces = <(int, double, double)>[
  (1, 0, 0), // 앞
  (6, 0, pi), // 뒤
  (3, 0, -pi / 2), // 오른쪽
  (4, 0, pi / 2), // 왼쪽
  (2, -pi / 2, 0), // 위
  (5, pi / 2, 0), // 아래
];

/// 그 눈을 앞면으로 가져오는 굴림 각도 (X, Y) — Z는 0(한 바퀴 단위)
const _toFront = <int, (double, double)>{
  1: (0, 0),
  6: (0, pi),
  3: (0, pi / 2),
  4: (0, -pi / 2),
  2: (pi / 2, 0),
  5: (-pi / 2, 0),
};

// 쉬는 자세: 위·오른쪽 면이 조금 보이게
const _tiltX = 0.42; // + = 윗면이 보이게
const _tiltY = 0.5; // + = 오른쪽 면이 보이게

class _DiceRollerState extends State<DiceRoller> with SingleTickerProviderStateMixin {
  static const _maxDice = 3;
  final _rand = Random();
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() {});
        HapticFeedback.mediumImpact();
      }
    });

  int _count = 1;
  List<int> _final = [1, 1, 1];
  // 주사위마다 굴림 각도 (X, Y, Z): 시작 → 끝
  List<List<double>> _from = List.generate(_maxDice, (_) => [0.0, 0.0, 0.0]);
  List<List<double>> _to = List.generate(_maxDice, (_) => [0.0, 0.0, 0.0]);
  List<double> _delay = List.filled(_maxDice, 0);

  bool get _rolling => _c.isAnimating;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // 지금 각도 (굴리는 중이면 중간)
  List<double> _angles(int i) {
    final t = _t(i);
    final e = Curves.easeOutCubic.transform(t);
    return [for (var k = 0; k < 3; k++) _from[i][k] + (_to[i][k] - _from[i][k]) * e];
  }

  double _t(int i) => _rolling ? ((_c.value - _delay[i]) / (1 - _delay[i])).clamp(0.0, 1.0) : 1.0;

  // start에서 dir 방향으로 turns 바퀴쯤 돈 뒤 target(한 바퀴 단위로 같은 각)에 닿는 각
  double _land(double start, double target, double turns, int dir) {
    final want = start + dir * turns * 2 * pi;
    final k = ((want - target) / (2 * pi)).round();
    return target + k * 2 * pi;
  }

  void _roll() {
    if (_rolling) return;
    _final = List.generate(_maxDice, (_) => _rand.nextInt(6) + 1);
    for (var i = 0; i < _maxDice; i++) {
      final now = _angles(i);
      final (tx, ty) = _toFront[_final[i]]!;
      int dir() => _rand.nextBool() ? 1 : -1;
      _from[i] = now;
      _to[i] = [
        _land(now[0], tx, 2 + _rand.nextDouble() * 1.5, dir()),
        _land(now[1], ty, 2 + _rand.nextDouble() * 1.5, dir()),
        _land(now[2], 0, 0.5 + _rand.nextDouble(), dir()),
      ];
    }
    _delay = List.generate(_maxDice, (i) => i == 0 ? 0 : _rand.nextDouble() * 0.12);
    HapticFeedback.selectionClick();
    _c.forward(from: 0);
  }

  Widget _die(int i, double size) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _t(i);
        final a = _angles(i);
        // 튀기: 세 번, 점점 낮게
        final hop = (sin(t * pi * 3)).abs() * pow(1 - t, 1.3) * size * 0.6;
        final lift = (hop / (size * 0.6)).clamp(0.0, 1.0);
        final h = size / 2;
        // 몸통(굴림 + 쉬는 자세 + 튀기) — 면마다 이것 × 면 자리
        Matrix4 body() => Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..multiply(Matrix4.translationValues(0, -hop, 0))
          ..multiply(Matrix4.rotationX(_tiltX))
          ..multiply(Matrix4.rotationY(_tiltY))
          ..multiply(Matrix4.rotationX(a[0]))
          ..multiply(Matrix4.rotationY(a[1]))
          ..multiply(Matrix4.rotationZ(a[2]));
        final faces = <Widget>[];
        for (final (value, fx, fy) in _faces) {
          // 이 면의 바깥 방향(처음엔 화면 쪽 -z)을 같은 순서로 돌려 봄
          _V n = (x: 0, y: 0, z: -1);
          n = _rotY(n, fy);
          n = _rotX(n, fx);
          n = _rotZ(n, a[2]);
          n = _rotY(n, a[1]);
          n = _rotX(n, a[0]);
          n = _rotY(n, _tiltY);
          n = _rotX(n, _tiltX);
          if (n.z > -0.02) continue; // 뒤쪽을 보는 면은 안 그림
          final m = body()
            ..multiply(Matrix4.rotationX(fx))
            ..multiply(Matrix4.rotationY(fy))
            ..multiply(Matrix4.translationValues(0, 0, -h));
          // 빛: 왼쪽 위 앞에서 — 화면 쪽을 많이 볼수록, 위를 볼수록 밝게
          final light = (-n.z * 0.75 + -n.y * 0.35 + -n.x * 0.1).clamp(0.0, 1.0);
          faces.add(Transform(
            alignment: Alignment.center,
            transform: m,
            child: _DieFace(value: value, size: size, shade: (1 - light) * 0.45),
          ));
        }
        return SizedBox(
          width: size * 1.6,
          height: size * 2.1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 바닥 그림자 — 높이 뜨면 작고 흐리게
              Positioned(
                bottom: size * 0.12,
                child: Container(
                  width: size * (1.1 - 0.45 * lift),
                  height: size * 0.16,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18 - 0.12 * lift),
                    borderRadius: BorderRadius.circular(size),
                  ),
                ),
              ),
              Positioned(
                bottom: size * 0.42,
                child: SizedBox(width: size, height: size, child: Stack(children: faces)),
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
      final size = min(170.0, min(box.maxWidth / (_count * 1.7 + 0.3), box.maxHeight * 0.26));
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

/// 주사위 한 면 (점 1~6, 모두 검정) — shade: 그늘 진하기(0~0.45)
class _DieFace extends StatelessWidget {
  final int value;
  final double size;
  final double shade;
  const _DieFace({required this.value, required this.size, required this.shade});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color.lerp(const Color(0xFFFFFDF8), const Color(0xFF8C8174), shade),
        borderRadius: BorderRadius.circular(size * 0.1),
        border: Border.all(color: Color.lerp(const Color(0xFFE6DED2), const Color(0xFF6E655A), shade)!, width: 1.5),
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
    final paint = Paint()..color = kInk;
    for (final k in _layout[value] ?? const <int>[]) {
      final cx = size.width * (0.25 + 0.25 * (k % 3));
      final cy = size.height * (0.25 + 0.25 * (k ~/ 3));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipPainter old) => old.value != value;
}
