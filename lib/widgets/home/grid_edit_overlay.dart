import 'package:flutter/material.dart';
import 'package:boardpad/models/home_layout.dart';

/// 관리자 미리보기 위에 겹쳐서 위젯을 끌어 옮기고(이동) 손잡이로 크기를 바꾸는 층.
/// 1280×800 기준 좌표에서 동작하고, 바깥의 FittedBox가 줄여서 보여 줌.
/// 놓는 순간 규칙에 안 맞으면(겹침, 허용 안 되는 크기) 바뀌지 않고 onReject로 이유만 알림.
class GridEditOverlay extends StatefulWidget {
  final HomeLayout layout;
  final String? selectedId;
  final void Function(String? id) onSelect;
  final bool Function(GridItem next) onCommit;
  final void Function(String message) onReject;

  const GridEditOverlay({
    super.key,
    required this.layout,
    required this.selectedId,
    required this.onSelect,
    required this.onCommit,
    required this.onReject,
  });

  @override
  State<GridEditOverlay> createState() => _GridEditOverlayState();
}

enum _DragMode { move, resize }

const _orange = Color(0xFFE2711D);
const _ok = Color(0xFF2E9E5B);
const _bad = Color(0xFFD23C2C);

class _GridEditOverlayState extends State<GridEditOverlay> {
  final GlobalKey _areaKey = GlobalKey();

  GridItem? _dragItem; // 끌기 시작할 때의 위젯
  _DragMode? _mode;
  Offset _grab = Offset.zero; // 위젯 왼쪽 위에서 손가락까지 거리
  GridItem? _ghost; // 놓을 자리 후보
  String? _ghostProblem;

  HomeLayout get _layout => widget.layout;

  Offset _toLocal(Offset global) {
    final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  void _start(GridItem item, _DragMode mode, Offset global) {
    final rect = _layout.cellRect(item.x, item.y, item.w, item.h);
    setState(() {
      _dragItem = item;
      _mode = mode;
      _grab = _toLocal(global) - rect.topLeft;
      _ghost = item;
      _ghostProblem = null;
    });
    widget.onSelect(item.id);
  }

  void _update(Offset global) {
    final item = _dragItem;
    if (item == null) return;
    final p = _toLocal(global);
    final stepX = _layout.cellWidth + HomeLayout.gap;
    final stepY = _layout.cellHeight + HomeLayout.gap;
    GridItem next;
    if (_mode == _DragMode.move) {
      final topLeft = p - _grab;
      var x = ((topLeft.dx - _layout.gridLeft) / stepX).round();
      var y = ((topLeft.dy - _layout.gridTop) / stepY).round();
      x = x.clamp(0, _layout.cols - item.w).toInt();
      y = y.clamp(0, HomeLayout.rows - item.h).toInt();
      next = item.copyWith(x: x, y: y);
    } else {
      final origin = _layout.cellRect(item.x, item.y, 1, 1);
      var w = ((p.dx - origin.left + HomeLayout.gap) / stepX).round();
      var h = ((p.dy - origin.top + HomeLayout.gap) / stepY).round();
      w = w.clamp(1, _layout.cols - item.x).toInt();
      h = h.clamp(1, HomeLayout.rows - item.y).toInt();
      next = item.copyWith(w: w, h: h);
    }
    if (next.x != _ghost?.x || next.y != _ghost?.y || next.w != _ghost?.w || next.h != _ghost?.h) {
      setState(() {
        _ghost = next;
        _ghostProblem = _layout.problemFor(next);
      });
    }
  }

  void _end() {
    final item = _dragItem;
    final ghost = _ghost;
    final problem = _ghostProblem;
    setState(() {
      _dragItem = null;
      _mode = null;
      _ghost = null;
      _ghostProblem = null;
    });
    if (item == null || ghost == null) return;
    final changed = ghost.x != item.x || ghost.y != item.y || ghost.w != item.w || ghost.h != item.h;
    if (!changed) return;
    if (problem != null) {
      widget.onReject(problem);
      return;
    }
    widget.onCommit(ghost);
  }

  @override
  Widget build(BuildContext context) {
    final dragging = _dragItem != null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => widget.onSelect(null),
      child: Stack(
        key: _areaKey,
        children: [
          // 끄는 동안 칸 표시
          if (dragging)
            for (var y = 0; y < HomeLayout.rows; y++)
              for (var x = 0; x < _layout.cols; x++)
                Positioned.fromRect(
                  rect: _layout.cellRect(x, y, 1, 1),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x14E2711D),
                        border: Border.all(color: const Color(0x66E2711D)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
          for (final item in _layout.widgets) _itemLayer(item),
          if (_ghost != null) _ghostLayer(_ghost!),
        ],
      ),
    );
  }

  Widget _itemLayer(GridItem item) {
    final rect = _layout.cellRect(item.x, item.y, item.w, item.h);
    final selected = item.id == widget.selectedId;
    final isDragged = item.id == _dragItem?.id;
    return Positioned.fromRect(
      rect: rect,
      child: MouseRegion(
        cursor: isDragged ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelect(item.id),
          onPanStart: (d) => _start(item, _DragMode.move, d.globalPosition),
          onPanUpdate: (d) => _update(d.globalPosition),
          onPanEnd: (_) => _end(),
          onPanCancel: _end,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDragged ? const Color(0x55FFFFFF) : Colors.transparent,
                    border: Border.all(
                      color: selected ? _orange : Colors.transparent,
                      width: 5,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
              if (selected && !isDragged)
                Positioned(
                  // 위젯 안쪽에 둬야 눌림 (밖으로 나간 부분은 터치가 안 잡힘)
                  right: 8,
                  bottom: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _start(item, _DragMode.resize, d.globalPosition),
                      onPanUpdate: (d) => _update(d.globalPosition),
                      onPanEnd: (_) => _end(),
                      onPanCancel: _end,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: _orange, width: 4),
                          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.open_in_full, size: 20, color: _orange),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ghostLayer(GridItem ghost) {
    final rect = _layout.cellRect(ghost.x, ghost.y, ghost.w, ghost.h);
    final ok = _ghostProblem == null;
    final color = ok ? _ok : _bad;
    final label = ok ? '${ghost.w}×${ghost.h} · 여기에 놓기' : _ghostProblem!;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  border: Border.all(color: color, width: 5),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              right: 12,
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
