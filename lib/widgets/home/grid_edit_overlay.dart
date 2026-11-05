import 'package:flutter/material.dart';
import 'package:boardpad/models/home_layout.dart';

/// 관리자 미리보기 위에 겹쳐서 위젯을 끌어 옮기고(이동) 손잡이로 크기를 바꾸는 층.
/// 1280×800 기준 좌표에서 동작하고, 바깥의 FittedBox가 줄여서 보여 줌.
/// - 빈 칸에 놓으면 옮기고, 다른 위젯 위에 놓으면 자리 바꾸기(HomeLayout.swapFor)를 시도.
/// - 보관함 위로 끌어 놓으면 onPark (보관함은 미리보기 밖에 있어서 isOverParking으로 위치를 물어봄).
/// - 보관함 위젯(`Draggable<String>`, 데이터는 위젯 id)을 이 위에 놓으면 onUnpark.
/// 놓는 순간 규칙에 안 맞으면 바뀌지 않고 onReject로 이유만 알림.
class GridEditOverlay extends StatefulWidget {
  final HomeLayout layout;
  final String? selectedId;
  final void Function(String? id) onSelect;
  final bool Function(GridItem next) onCommit;
  final void Function(List<GridItem> widgets, String message) onSwap;
  final void Function(String message) onReject;
  final bool Function(Offset global)? isOverParking;
  final void Function(bool over)? onParkingHover;
  final void Function(GridItem item)? onPark;
  final void Function(GridItem placed)? onUnpark;

  /// 위젯을 옮기기 시작/끝 (보관함을 크게 펼쳐서 놓기 쉽게)
  final void Function(bool moving)? onMoveDragChanged;

  const GridEditOverlay({
    super.key,
    required this.layout,
    required this.selectedId,
    required this.onSelect,
    required this.onCommit,
    required this.onSwap,
    required this.onReject,
    this.isOverParking,
    this.onParkingHover,
    this.onPark,
    this.onUnpark,
    this.onMoveDragChanged,
  });

  @override
  State<GridEditOverlay> createState() => _GridEditOverlayState();
}

enum _DragMode { move, resize }

const _orange = Color(0xFFE2711D);
const _ok = Color(0xFF2E9E5B);
const _swapColor = Color(0xFF2F6FD6);
const _bad = Color(0xFFD23C2C);

typedef _Swap = ({List<GridItem> widgets, GridItem moved, List<GridItem> displaced});

class _GridEditOverlayState extends State<GridEditOverlay> {
  final GlobalKey _areaKey = GlobalKey();

  GridItem? _dragItem; // 끌기 시작할 때의 위젯
  _DragMode? _mode;
  Offset _grab = Offset.zero; // 위젯 왼쪽 위에서 손가락까지 거리
  GridItem? _target; // 손가락 위치로 계산한 자리 (바뀔 때만 다시 계산)
  GridItem? _ghost; // 실제로 놓일 자리 후보
  String? _ghostProblem;
  _Swap? _swap; // 자리 바꾸기가 되면 그 결과
  bool _overParking = false;

  // 보관함에서 끌어오는 중
  GridItem? _unparkGhost;
  String? _unparkProblem;

  HomeLayout get _layout => widget.layout;

  Offset _toLocal(Offset global) {
    final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  void _setParkingHover(bool over) {
    if (_overParking == over) return;
    setState(() => _overParking = over);
    widget.onParkingHover?.call(over);
  }

  void _start(GridItem item, _DragMode mode, Offset global) {
    final rect = _layout.cellRect(item.x, item.y, item.w, item.h);
    setState(() {
      _dragItem = item;
      _mode = mode;
      _grab = _toLocal(global) - rect.topLeft;
      _target = item;
      _ghost = item;
      _ghostProblem = null;
      _swap = null;
    });
    widget.onSelect(item.id);
    if (mode == _DragMode.move) widget.onMoveDragChanged?.call(true);
  }

  void _update(Offset global) {
    final item = _dragItem;
    if (item == null) return;
    if (_mode == _DragMode.move && widget.isOverParking?.call(global) == true) {
      _setParkingHover(true);
      return;
    }
    _setParkingHover(false);
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
    final t = _target;
    if (t != null && next.x == t.x && next.y == t.y && next.w == t.w && next.h == t.h) return;
    var problem = _layout.problemFor(next);
    _Swap? swap;
    if (problem != null && _mode == _DragMode.move) {
      swap = _layout.swapFor(next);
      if (swap != null) problem = null;
    }
    setState(() {
      _target = next;
      _ghost = swap?.moved ?? next;
      _ghostProblem = problem;
      _swap = swap;
    });
  }

  void _end() {
    final item = _dragItem;
    final ghost = _ghost;
    final problem = _ghostProblem;
    final swap = _swap;
    final parked = _overParking;
    final wasMoving = _mode == _DragMode.move;
    setState(() {
      _dragItem = null;
      _mode = null;
      _target = null;
      _ghost = null;
      _ghostProblem = null;
      _swap = null;
    });
    _setParkingHover(false);
    if (wasMoving) widget.onMoveDragChanged?.call(false);
    if (item == null) return;
    if (parked) {
      widget.onPark?.call(item);
      return;
    }
    if (ghost == null) return;
    final changed = ghost.x != item.x || ghost.y != item.y || ghost.w != item.w || ghost.h != item.h;
    if (!changed) return;
    if (swap != null) {
      widget.onSwap(swap.widgets, '${_names(swap.displaced)}와(과) 자리를 바꿨어요.');
      return;
    }
    if (problem != null) {
      widget.onReject(problem);
      return;
    }
    widget.onCommit(ghost);
  }

  String _names(List<GridItem> items) => items.map((e) => specOf(e.type)?.name ?? '위젯').join(', ');

  // ── 보관함에서 끌어오기 ──

  GridItem? _parkedById(String id) {
    for (final p in _layout.parked) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _unparkMove(String id, Offset global) {
    final item = _parkedById(id);
    if (item == null) return;
    final p = _toLocal(global);
    final cx = ((p.dx - _layout.gridLeft) / (_layout.cellWidth + HomeLayout.gap)).floor();
    final cy = ((p.dy - _layout.gridTop) / (_layout.cellHeight + HomeLayout.gap)).floor();
    final (placed, problem) = _layout.placeParked(item, cx, cy);
    final g = _unparkGhost;
    if (g != null && g.x == placed.x && g.y == placed.y && g.w == placed.w && g.h == placed.h) return;
    setState(() {
      _unparkGhost = placed;
      _unparkProblem = problem;
    });
  }

  void _unparkClear() {
    if (_unparkGhost == null) return;
    setState(() {
      _unparkGhost = null;
      _unparkProblem = null;
    });
  }

  void _unparkDrop(String id, Offset global) {
    _unparkMove(id, global);
    final placed = _unparkGhost;
    final problem = _unparkProblem;
    _unparkClear();
    if (placed == null) return;
    if (problem != null) {
      widget.onReject(problem);
      return;
    }
    widget.onUnpark?.call(placed);
  }

  @override
  Widget build(BuildContext context) {
    final showCells = (_dragItem != null && !_overParking) || _unparkGhost != null;
    final dragged = _dragItem;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => widget.onUnpark != null && _parkedById(d.data) != null,
      onMove: (d) => _unparkMove(d.data, d.offset),
      onLeave: (_) => _unparkClear(),
      onAcceptWithDetails: (d) => _unparkDrop(d.data, d.offset),
      builder: (context, _, _) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => widget.onSelect(null),
        child: Stack(
          key: _areaKey,
          children: [
            // 끄는 동안 칸 표시
            if (showCells)
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
            // 자리 바꾸기로 밀려날 위젯들이 갈 자리
            if (_swap != null)
              for (final d in _swap!.displaced) _displacedLayer(d),
            if (_ghost != null && !_overParking) _ghostLayer(_ghost!, _ghostProblem, swapping: _swap != null),
            if (_unparkGhost != null) _ghostLayer(_unparkGhost!, _unparkProblem, label: '보관함에서 꺼내기'),
            // 보관함 위로 끌고 있을 때: 원래 자리에 안내
            if (dragged != null && _overParking) _parkHintLayer(dragged),
          ],
        ),
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

  Widget _label(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ghostLayer(GridItem ghost, String? problem, {bool swapping = false, String? label}) {
    final rect = _layout.cellRect(ghost.x, ghost.y, ghost.w, ghost.h);
    final ok = problem == null;
    final color = !ok ? _bad : (swapping ? _swapColor : _ok);
    final text = !ok
        ? problem
        : swapping
            ? '${_names(_swap!.displaced)}와(과) 자리 바꾸기'
            : '${ghost.w}×${ghost.h} · ${label ?? '여기에 놓기'}';
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
                child: _label(text, color, icon: swapping ? Icons.swap_horiz : null),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _displacedLayer(GridItem d) {
    final rect = _layout.cellRect(d.x, d.y, d.w, d.h);
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _swapColor.withValues(alpha: 0.10),
            border: Border.all(color: _swapColor.withValues(alpha: 0.7), width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: Opacity(
              opacity: 0.85,
              child: _label('${specOf(d.type)?.name ?? '위젯'} → 여기로', _swapColor, icon: Icons.subdirectory_arrow_right),
            ),
          ),
        ),
      ),
    );
  }

  Widget _parkHintLayer(GridItem item) {
    final rect = _layout.cellRect(item.x, item.y, item.w, item.h);
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _orange.withValues(alpha: 0.15),
            border: Border.all(color: _orange, width: 5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(child: _label('놓으면 보관함으로', _orange, icon: Icons.archive_outlined)),
        ),
      ),
    );
  }
}
