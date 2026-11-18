import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/widgets/home/home_theme.dart';

/// 게임도구 '주사위' (126차, 127차 입체, 128차 결과 표시, 129차 둥근 모서리 한 덩어리, 130차 셰이더)
///   - 130차: shaders/dice.frag(레이마칭 — 화면 점마다 빛 계산: 오목한 눈·둥근 모서리 반사광·은은한 그늘·매끈한 윤곽)로 그림.
///     셰이더를 못 불러오면(옛 웹 렌더러 등) 아래 129차 삼각형 망으로 그림
///   - 129차: 면 6장을 따로 붙이던 것(이음매가 떨어져 보여 싸구려 같음) → 모서리가 둥근 정육면체 하나를 삼각형 망(mesh)으로 그림
///     (각 면을 10×10 칸으로 나눈 점을 '둥근 상자' 모양으로 당겨 모서리·꼭짓점이 매끈하게 이어짐),
///     점마다 빛(왼쪽 위 앞에서 오는 빛 + 은은한 반사광)으로 밝기를 매겨 부드러운 입체감, 뒤쪽 칸은 빼고 먼 칸부터 그림
///   - 눈(점)은 보이는 면 위에 원을 같은 방식으로 돌려 그림 — 모두 검정, 1은 조금 크게. 마주 보는 면의 합 7
///   - 굴리면 1.4초 동안 세 번 튀면서(점점 낮게) 여러 바퀴 구르다 나온 눈이 앞면으로 오며 멈춤, 멈추면 아래에 결과 숫자(여러 개면 합계)
///   - 쉴 때는 앞면이 크게 보이게 조금만 기울이고, 구르는 동안만 더 기울어짐. 주사위 1~3개, 주사위를 눌러도 굴러감
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

/// 면: 눈 · 바깥 방향 n · 면 위 가로 u · 세로 v  (화면 좌표: x 오른쪽, y 아래, z 화면 안쪽(멀어짐) — 화면 쪽 = -z)
const _faces = <(int, _V, _V, _V)>[
  (1, (x: 0, y: 0, z: -1), (x: 1, y: 0, z: 0), (x: 0, y: 1, z: 0)), // 앞
  (6, (x: 0, y: 0, z: 1), (x: -1, y: 0, z: 0), (x: 0, y: 1, z: 0)), // 뒤
  (3, (x: 1, y: 0, z: 0), (x: 0, y: 0, z: 1), (x: 0, y: 1, z: 0)), // 오른쪽
  (4, (x: -1, y: 0, z: 0), (x: 0, y: 0, z: -1), (x: 0, y: 1, z: 0)), // 왼쪽
  (2, (x: 0, y: -1, z: 0), (x: 1, y: 0, z: 0), (x: 0, y: 0, z: 1)), // 위
  (5, (x: 0, y: 1, z: 0), (x: 1, y: 0, z: 0), (x: 0, y: 0, z: -1)), // 아래
];

_V _add(_V a, _V b) => (x: a.x + b.x, y: a.y + b.y, z: a.z + b.z);
_V _mul(_V a, double k) => (x: a.x * k, y: a.y * k, z: a.z * k);
double _dot(_V a, _V b) => a.x * b.x + a.y * b.y + a.z * b.z;
_V _norm(_V a) {
  final l = sqrt(_dot(a, a));
  return l < 1e-9 ? a : _mul(a, 1 / l);
}

/// 둥근 상자 망 (한 번만 만듦): 면마다 (N+1)² 점 — 위치·법선(바깥 방향), 반지름 _round
const _grid = 10;
const _round = 0.3;
class _Mesh {
  final List<_V> pos = [];
  final List<_V> nrm = [];
  final List<List<int>> quads = []; // 칸마다 점 4개 번호
  _Mesh() {
    // 가장자리 쪽에 칸이 촘촘하게 (모서리 곡면이 매끈하게)
    final ts = [for (var i = 0; i <= _grid; i++) sin(pi * (i / _grid - 0.5))];
    const lim = 1 - _round;
    for (final (_, n, u, v) in _faces) {
      final base = pos.length;
      for (final a in ts) {
        for (final b in ts) {
          final p = _add(n, _add(_mul(u, a), _mul(v, b)));
          final inner = (x: p.x.clamp(-lim, lim), y: p.y.clamp(-lim, lim), z: p.z.clamp(-lim, lim));
          final d = _add(p, _mul(inner, -1));
          final nn = _norm(d);
          pos.add(_add(inner, _mul(nn, _round)));
          nrm.add(nn);
        }
      }
      for (var i = 0; i < _grid; i++) {
        for (var j = 0; j < _grid; j++) {
          final k = base + i * (_grid + 1) + j;
          quads.add([k, k + 1, k + _grid + 2, k + _grid + 1]);
        }
      }
    }
  }
}

final _mesh = _Mesh();

/// 130차: 주사위 셰이더 — 앱에서 한 번만 불러옴 (못 불러오면 null → 삼각형 망으로)
class _DiceShader {
  static Future<ui.FragmentProgram?>? _future;
  static Future<ui.FragmentProgram?> load() => _future ??= ui.FragmentProgram.fromAsset('shaders/dice.frag')
      .then<ui.FragmentProgram?>((p) => p)
      .catchError((Object e) {
        debugPrint('주사위 셰이더를 못 불러와서 삼각형 망으로 그려요: $e');
        return null;
      });
}

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
const _restX = 0.3, _restY = 0.36;
const _rollX = 0.55, _rollY = 0.62;

class _DiceRollerState extends State<DiceRoller> with SingleTickerProviderStateMixin {
  static const _maxDice = 3;
  final _rand = Random();
  bool _rolled = false; // 한 번이라도 굴렸는지 (결과 숫자 표시)
  ui.FragmentProgram? _program; // 130차 셰이더 (불러오기 전·실패면 null)

  @override
  void initState() {
    super.initState();
    _DiceShader.load().then((p) {
      if (mounted && p != null) setState(() => _program = p);
    });
  }
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
        final bend = sin(pi * t); // 구르는 동안만 더 기울어짐 (처음·끝은 쉬는 자세)
        return CustomPaint(
          size: Size(size * 1.75, size * 2.0),
          painter: _DiePainter(
            ax: a[0],
            ay: a[1],
            az: a[2],
            tiltX: _restX + (_rollX - _restX) * bend,
            tiltY: _restY + (_rollY - _restY) * bend,
            hop: hop,
            dieSize: size,
            program: _program,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sum = _final.take(_count).fold<int>(0, (a, b) => a + b);
    return LayoutBuilder(builder: (context, box) {
      final size = min(180.0, min(box.maxWidth / (_count * 1.85 + 0.3), box.maxHeight * 0.26));
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

/// 둥근 주사위 한 개 그리기 (129차)
class _DiePainter extends CustomPainter {
  final double ax, ay, az, tiltX, tiltY, hop, dieSize;
  final ui.FragmentProgram? program;
  _DiePainter({
    this.program,
    required this.ax,
    required this.ay,
    required this.az,
    required this.tiltX,
    required this.tiltY,
    required this.hop,
    required this.dieSize,
  });

  // 3×3 칸 중 점 자리 (0~8: 왼쪽 위부터)
  static const _layout = {
    1: [4],
    2: [2, 6],
    3: [2, 4, 6],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };
  static final _light = _norm((x: -0.35, y: -0.55, z: -0.75)); // 표면 → 빛 방향 (왼쪽 위 앞)
  static final _half = _norm(_add(_light, (x: 0, y: 0, z: -1))); // 반사광용
  static const _body = Color(0xFFF7F2E8);

  // 굴림 → 쉬는 자세 순서 (Matrix4 rotationX·Y·Z 곱과 같은 순서)
  _V _rot(_V v) => _rotX(_rotY(_rotX(_rotY(_rotZ(v, az), ay), ax), tiltY), tiltX);

  Color _shade(_V n, Color base, {double spec = 0.35}) {
    final diff = max(0.0, _dot(n, _light));
    final sp = pow(max(0.0, _dot(n, _half)), 28) * spec;
    final k = 0.62 + 0.38 * diff;
    int ch(double c) => (c * k * 255 + sp * 255).clamp(0, 255).round();
    return Color.fromARGB(255, ch(base.r), ch(base.g), ch(base.b));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = dieSize * 0.5; // 상자 반 크기(망 좌표 ±1)
    final center = Offset(size.width / 2, size.height - dieSize * 0.78 - hop);
    const d = 7.0; // 원근 — 작을수록 강함
    Offset proj(_V p) {
      final k = d / (d + p.z);
      return center + Offset(p.x * s * k, p.y * s * k);
    }

    // 바닥 그림자 — 높이 뜨면 작고 옅게
    final lift = (hop / (dieSize * 0.6)).clamp(0.0, 1.0);
    final floorY = size.height - dieSize * 0.78 + s * 1.05;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width / 2, floorY), width: dieSize * (1.05 - 0.4 * lift), height: dieSize * 0.16),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.26 - 0.16 * lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, dieSize * 0.06),
    );

    // 130차: 셰이더로 — 사각형(한 변 = 주사위 한 변 × 1.75) 안을 셰이더가 칠함. uniform 순서는 shaders/dice.frag와 같게
    final prog = program;
    if (prog != null) {
      final side = dieSize * 1.75;
      final rect = Rect.fromCenter(center: center, width: side, height: side);
      final c0 = _rot((x: 1, y: 0, z: 0)), c1 = _rot((x: 0, y: 1, z: 0)), c2 = _rot((x: 0, y: 0, z: 1));
      final sh = prog.fragmentShader();
      var i = 0;
      for (final f in [side, side, rect.left, rect.top, c0.x, c0.y, c0.z, c1.x, c1.y, c1.z, c2.x, c2.y, c2.z]) {
        sh.setFloat(i++, f);
      }
      canvas.drawRect(rect, Paint()..shader = sh);
      return;
    }

    // 몸통(셰이더가 없을 때 — 129차): 칸마다 화면 쪽인 것만, 먼 칸부터
    final p = [for (final v in _mesh.pos) _rot(v)];
    final n = [for (final v in _mesh.nrm) _rot(v)];
    final quads = <(double, List<int>)>[];
    for (final q in _mesh.quads) {
      final nz = n[q[0]].z + n[q[1]].z + n[q[2]].z + n[q[3]].z;
      if (nz > 0.2) continue;
      quads.add((p[q[0]].z + p[q[1]].z + p[q[2]].z + p[q[3]].z, q));
    }
    quads.sort((x, y) => y.$1.compareTo(x.$1));
    final colors = [for (final v in n) _shade(v, _body)];
    final pts = <Offset>[];
    final cols = <Color>[];
    for (final (_, q) in quads) {
      for (final k in [q[0], q[1], q[2], q[0], q[2], q[3]]) {
        pts.add(proj(p[k]));
        cols.add(colors[k]);
      }
    }
    canvas.drawVertices(ui.Vertices(ui.VertexMode.triangles, pts, colors: cols), BlendMode.dst, Paint());

    // 눈: 화면 쪽 면 위에 원(조금 눌린 홈처럼 가장자리를 밝게)
    for (final (value, fn, u, v) in _faces) {
      final nn = _rot(fn);
      if (nn.z > -0.08) continue;
      final pip = _shade(nn, const Color(0xFF231C16), spec: 0.12);
      final rim = _shade(nn, const Color(0xFFFFFFFF), spec: 0);
      final r = value == 1 ? 0.25 : 0.19;
      for (final k in _layout[value]!) {
        final cu = (k % 3 - 1) * 0.52, cv = (k ~/ 3 - 1) * 0.52;
        Path ring(double rr, double shift) {
          final path = Path();
          for (var j = 0; j <= 20; j++) {
            final th = j / 20 * 2 * pi;
            final local = _add(fn, _add(_mul(u, cu + cos(th) * rr), _mul(v, cv + sin(th) * rr + shift)));
            final o = proj(_rot(local));
            j == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
          }
          return path..close();
        }

        canvas.drawPath(ring(r * 1.08, r * 0.06), Paint()..color = rim.withValues(alpha: 0.85));
        canvas.drawPath(ring(r, 0), Paint()..color = pip);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DiePainter o) =>
      o.ax != ax ||
      o.ay != ay ||
      o.az != az ||
      o.tiltX != tiltX ||
      o.tiltY != tiltY ||
      o.hop != hop ||
      o.dieSize != dieSize ||
      o.program != program;
}
