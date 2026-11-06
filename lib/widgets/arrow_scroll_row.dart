import 'package:flutter/material.dart';
import 'package:boardpad/widgets/admin_colors.dart';

/// 가로로 넘치는 버튼 줄 + 좌우 화살표.
/// 내용이 화면 폭보다 길 때만 화살표가 나타나고, 더 갈 곳이 없는 쪽 화살표는 숨김.
/// 화살표를 누르면 보이는 폭의 80%만큼 부드럽게 넘어감. (PC에서 마우스 휠로 가로 이동이 어려워서)
class ArrowScrollRow extends StatefulWidget {
  final List<Widget> children;
  final Color arrowColor;
  final double height;

  const ArrowScrollRow({
    super.key,
    required this.children,
    this.arrowColor = kAdminAccent,
    this.height = 44,
  });

  @override
  State<ArrowScrollRow> createState() => _ArrowScrollRowState();
}

class _ArrowScrollRowState extends State<ArrowScrollRow> {
  final ScrollController _c = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(covariant ArrowScrollRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 카테고리가 늘거나 줄면 화살표 다시 계산
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  void _update() {
    if (!mounted || !_c.hasClients) return;
    final p = _c.position;
    final left = p.pixels > 1;
    final right = p.pixels < p.maxScrollExtent - 1;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _go(int dir) {
    if (!_c.hasClients) return;
    final p = _c.position;
    final target = (p.pixels + dir * p.viewportDimension * 0.8).clamp(0.0, p.maxScrollExtent);
    _c.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _c.removeListener(_update);
    _c.dispose();
    super.dispose();
  }

  Widget _arrow(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: CircleBorder(side: BorderSide(color: widget.arrowColor.withValues(alpha: 0.5))),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 36, height: 36, child: Icon(icon, color: widget.arrowColor)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: NotificationListener<ScrollMetricsNotification>(
        // 창 크기가 바뀌어 넘침 여부가 달라질 때도 화살표 갱신
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _update());
          return false;
        },
        child: Row(
          children: [
            if (_canLeft) ...[_arrow(Icons.chevron_left, () => _go(-1)), const SizedBox(width: 8)],
            Expanded(
              child: SingleChildScrollView(
                controller: _c,
                scrollDirection: Axis.horizontal,
                child: Row(children: widget.children),
              ),
            ),
            if (_canRight) ...[const SizedBox(width: 8), _arrow(Icons.chevron_right, () => _go(1))],
          ],
        ),
      ),
    );
  }
}
