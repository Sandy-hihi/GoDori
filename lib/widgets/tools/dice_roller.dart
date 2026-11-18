import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/widgets/home/home_theme.dart';

/// 게임도구 '주사위' (126차, 127차 입체 정육면체, 128차 완성도·결과 표시)
///   - 면 6개로 만든 정육면체(마주 보는 면의 합 7). 늘 살짝 기울여 앞·위·옆 세 면이 보임
///   - 굴리면 1.4초 동안 세 번 튀면서(점점 낮게) 세 방향으로 여러 바퀴 구르다 나온 눈이 앞면으로 오며 멈춤
///     (지금 자리에서 이어서 굴러감 — 끊기지 않음), 면마다 빛을 받는 정도로 밝기 다르게, 바닥 그림자, 멈출 때 진동
///   - 주사위 1~3개(2개 이상이면 합계), 주사위를 눌러도 굴러감. 눈은 모두 검정(127차)
///   - 128차: 멈출 땐 거의 정면으로 돌아와 나온 눈(앞면)이 또렷하게 + 앞면 주황 테두리 + 아래에 결과 숫자(여러 개면 '3 + 5 = 8'),
///     면 그라데이션·홈 파인 눈·흐린 그림자, 굴릴 때만 더 기울어짐
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

// 기울기: 쉴 때(멈춘 뒤)는 거의 정면 — 위·오른쪽 면이 얇게만 보여 나온 눈(앞면)이 또렷하게, 구르는 동안은 더 기울어짐
// + X = 윗면이 보이게, + Y = 오른쪽 면이 보이게
const _restX = 0.24, _restY = 0.3;
const _rollX = 0.55, _rollY = 0.62;

class _DiceRollerState extends State<DiceRoller> with SingleTickerProviderStateMixin {
  static const _maxDice = 3;
  final _rand = Random();
  bool _rolled = false; // 한 번이라도 굴렸는지 (결과 숫자 표시)
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
    _rolled = true;
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
        final h = size / 2 * 0.995; // 이음매 틈이 안 보이게 살짝 안쪽
        final bend = sin(pi * t); // 구르는 동안만 더 기울어짐 (처음·끝은 쉬는 자세)
        final tiltX = _restX + (_rollX - _restX) * bend;
        final tiltY = _restY + (_rollY - _restY) * bend;
        final landed = !_rolling && _rolled;
        // 몸통(굴림 + 쉬는 자세 + 튀기) — 면마다 이것 × 면 자리
        Matrix4 body() => Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..multiply(Matrix4.translationValues(0, -hop, 0))
          ..multiply(Matrix4.rotationX(tiltX))
          ..multiply(Matrix4.rotationY(tiltY))
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
          n = _rotY(n, tiltY);
          n = _rotX(n, tiltX);
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
            child: _DieFace(
              value: value,
              size: size,
              shade: (1 - light) * 0.45,
              // 나온 눈(앞면) 표시 — 멈춘 뒤에만
              result: landed && value == _final[i],
            ),
          ));
        }
        return SizedBox(
          width: size * 1.6,
          height: size * 2.1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 바닥 그림자 — 흐린 타원, 높이 뜨면 작고 옅게
              Positioned(
                bottom: size * 0.16,
                child: Container(
                  width: size * (1.0 - 0.4 * lift),
                  height: size * 0.1,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28 - 0.18 * lift),
                        blurRadius: size * 0.12,
                        spreadRadius: size * 0.01,
                      ),
                    ],
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
      final size = min(180.0, min(box.maxWidth / (_count * 1.7 + 0.3), box.maxHeight * 0.26));
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
            // 128차: 결과 — 주사위마다 나온 눈 숫자(+ 여러 개면 합계), 멈춘 뒤 톡 나타남
            SizedBox(
              height: 72,
              child: !_rolled || _rolling
                  ? null
                  : TweenAnimationBuilder<double>(
                      key: ValueKey(_final.take(_count).join(',')),
                      tween: Tween(begin: 0.6, end: 1),
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutBack,
                      builder: (context, k, child) => Transform.scale(scale: k, child: child),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _count; i++) ...[
                            if (i > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text('+', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: kMuted)),
                              ),
                            _ResultBadge(_final[i]),
                          ],
                          if (_count > 1) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('=', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: kMuted)),
                            ),
                            Text('$sum', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: kOrange)),
                          ],
                        ],
                      ),
                    ),
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

/// 결과 숫자 칸 (128차)
class _ResultBadge extends StatelessWidget {
  final int value;
  const _ResultBadge(this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kOrange,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: kOrange.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Text('$value', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white)),
    );
  }
}

/// 주사위 한 면 (점 1~6, 모두 검정) — shade: 그늘 진하기(0~0.45), result: 나온 눈 표시(주황 테두리)
class _DieFace extends StatelessWidget {
  final int value;
  final double size;
  final double shade;
  final bool result;
  const _DieFace({required this.value, required this.size, required this.shade, this.result = false});

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(const Color(0xFFFFFEFB), const Color(0xFF8C8174), shade)!;
    final dark = Color.lerp(const Color(0xFFEDE6DA), const Color(0xFF6F665B), shade)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // 가운데가 밝고 가장자리로 갈수록 살짝 어두움 — 모서리가 둥글게 깎인 느낌
        gradient: RadialGradient(colors: [light, dark], radius: 0.95, center: const Alignment(-0.15, -0.2)),
        borderRadius: BorderRadius.circular(size * 0.08),
        border: Border.all(
          color: result ? kOrange : Color.lerp(const Color(0xFFDCD3C5), const Color(0xFF5E564C), shade)!,
          width: result ? 4 : 1.2,
        ),
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
    final r = size.width * (value == 1 ? 0.12 : 0.088);
    for (final k in _layout[value] ?? const <int>[]) {
      final c = Offset(size.width * (0.25 + 0.25 * (k % 3)), size.height * (0.25 + 0.25 * (k ~/ 3)));
      // 홈 파인 눈: 아래쪽 가장자리 밝은 테두리 + 위가 더 어두운 그라데이션
      canvas.drawCircle(c + Offset(0, r * 0.12), r, Paint()..color = Colors.white.withValues(alpha: 0.7));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, 0.35),
            colors: [Color(0xFF3A332C), Color(0xFF15110E)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PipPainter old) => old.value != value;
}
