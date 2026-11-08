import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'admin_store_settings_screen.dart';
import 'package:image_picker/image_picker.dart';

import 'package:boardpad/models/home_layout.dart';
import 'package:boardpad/services/home_layout_service.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/widgets/admin_dialog_width.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/widgets/home/grid_edit_overlay.dart';
import 'package:boardpad/widgets/home/home_view.dart';
import 'admin_event_manage_screen.dart';
import 'admin_game_manage_screen.dart';
import 'admin_menu_manage_screen.dart';
import 'admin_notice_manage_screen.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/usage_meter.dart';

/// 관리자 웹: 손님 패드 홈 화면 꾸미기 (1단계 — 목록으로 편집, 왼쪽은 실제 화면 미리보기)
class AdminHomeLayoutScreen extends StatefulWidget {
  const AdminHomeLayoutScreen({super.key});

  @override
  State<AdminHomeLayoutScreen> createState() => _AdminHomeLayoutScreenState();
}

const _adminNavy = Color(0xFF1E2B3C);
const _accent = Color(0xFFE2711D);

class _AdminHomeLayoutScreenState extends State<AdminHomeLayoutScreen> {
  HomeLayout? _layout;
  String _savedJson = '';
  String? _selectedId;
  int _tab = 0; // 0: 격자 위젯, 1: 왼쪽 영역
  bool _saving = false;

  /// 실행 취소용: 바꾸기 전 배치들 (최근 것이 끝). 불러올 때 비움
  final List<HomeLayout> _history = [];
  static const int _historyLimit = 50;

  /// 보관함 띠 (미리보기 밖이라 끌어 놓을 때 위치를 직접 확인)
  final GlobalKey _parkingKey = GlobalKey();
  bool _parkingHover = false;
  bool _movingWidget = false; // 미리보기에서 위젯을 끄는 중 → 보관함을 크게 펼침

  /// 좁은 화면(폰·아이패드 세로): 미리보기 아래 스크롤 영역 (보관함·목록이 여기 들어감)
  final GlobalKey _narrowScrollKey = GlobalKey();
  final ScrollController _narrowScroll = ScrollController();

  /// 이보다 좁으면(사이드바 뺀 폭) 미리보기 위·목록 아래로 쌓음 — 오른쪽 패널 420px가 안 들어감
  static const double _stackBelow = 860;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _narrowScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final layout = await HomeLayoutService.load();
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _savedJson = jsonEncode(layout.toMap());
      _history.clear();
    });
  }

  bool get _dirty => _layout != null && jsonEncode(_layout!.toMap()) != _savedJson;

  /// 배치를 바꾸는 곳은 모두 여기를 지나감 (실행 취소 기록)
  void _update(HomeLayout next) {
    final current = _layout;
    setState(() {
      if (current != null && jsonEncode(current.toMap()) != jsonEncode(next.toMap())) {
        _history.add(current);
        if (_history.length > _historyLimit) _history.removeAt(0);
      }
      _layout = next;
    });
  }

  void _undo() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    setState(() {
      _layout = prev;
      if (_selectedId != null && !prev.widgets.any((w) => w.id == _selectedId)) _selectedId = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('한 단계 되돌렸어요.'), duration: Duration(milliseconds: 1200)));
  }

  /// 바꾼 결과가 규칙에 맞을 때만 적용. 안 맞으면 그대로 두고 이유를 알려 줌
  bool _tryUpdate(HomeLayout next) {
    final before = _layout!.validate().toSet();
    final problems = next.validate().where((e) => !before.contains(e)).toList();
    if (problems.isNotEmpty) {
      _warn(problems.first);
      return false;
    }
    _update(next);
    return true;
  }

  void _warn(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.block, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: const Color(0xFFB33A2A),
        duration: const Duration(seconds: 3),
      ));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final layout = _layout!;
    final errors = layout.validate();
    if (errors.isNotEmpty) {
      _snack(errors.first);
      return;
    }
    setState(() => _saving = true);
    try {
      await HomeLayoutService.save(layout);
      _savedJson = jsonEncode(layout.toMap());
      _snack('저장했어요. 손님 패드에 바로 적용돼요.');
    } catch (e) {
      _snack('저장하지 못했어요. 인터넷 연결이나 Firestore 규칙을 확인해 주세요. ($e)');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefault() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기본 배치로 되돌릴까요?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('지금 편집 중인 배치가 기본 배치로 바뀌어요. 저장을 눌러야 손님 패드에 적용돼요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('되돌리기')),
        ],
      ),
    );
    if (ok == true) {
      _update(HomeLayout.defaults());
      setState(() => _selectedId = null);
    }
  }

  // 예시 배치 고르기 — 미리보기를 보고 하나를 고르면 편집 화면에 불러옴 (저장해야 매장에 적용)
  Future<void> _pickPreset() async {
    // 좁은 화면에서는 한 줄에 하나씩 (팝업 폭에 맞춤)
    final dialogWidth = adminDialogWidth(context, 920);
    final cardWidth = math.min(444.0, dialogWidth);
    final picked = await showDialog<HomeLayoutPreset>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('예시 배치 고르기', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final p in homeLayoutPresets)
                  SizedBox(
                    width: cardWidth,
                    child: Material(
                      color: const Color(0xFFF6F4F0),
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, p),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AspectRatio(
                                aspectRatio: HomeLayout.designWidth / HomeLayout.designHeight,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  // 미리보기는 눌러지지 않게
                                  child: IgnorePointer(
                                    child: FittedBox(child: HomeView(layout: p.layout, roomNumber: 1)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(p.description, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))],
      ),
    );
    if (picked == null || !mounted) return;
    if (_dirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('지금 편집 중인 배치를 바꿀까요?', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('저장하지 않은 변경 사항이 있어요. "${picked.name}" 배치로 바꾸면 사라져요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('바꾸기')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    // 로고 사진·매장 이름처럼 이미 설정한 왼쪽 영역 로고 정보는 그대로 가져감
    SidebarItem? currentLogo;
    for (final e in _layout!.sidebarItems) {
      if (e.type == 'logo') currentLogo = e;
    }
    final items = [
      for (final it in picked.layout.sidebarItems)
        if (it.type == 'logo' && currentLogo != null) currentLogo else it,
    ];
    _update(picked.layout.copyWith(sidebarItems: items));
    setState(() => _selectedId = null);
    _snack('"${picked.name}" 배치를 불러왔어요. 확인 후 "저장하고 매장에 적용"을 눌러 주세요.');
  }

  void _navigate(String screen) {
    final targets = <String, Widget>{
      'store': const AdminStoreSettingsScreen(),
      'menu': const AdminMenuManageScreen(),
      'game': const AdminGameManageScreen(),
      'event': const AdminEventManageScreen(),
      'notice': const AdminNoticeManageScreen(),
    };
    final target = targets[screen];
    if (target == null) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => target,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  // ── 격자 위젯 편집 ──

  Future<void> _addWidget() async {
    final layout = _layout!;
    final spec = await showDialog<WidgetSpec>(
      context: context,
      builder: (ctx) => _WidgetPickerDialog(
        placedTypes: layout.widgets.map((e) => e.type).toSet(),
        parkedTypes: layout.parked.map((e) => e.type).toSet(),
      ),
    );
    if (spec == null) return;
    for (final size in spec.sizes) {
      final spot = layout.findSpot(size.w, size.h);
      if (spot != null) {
        final item = GridItem(
          id: 'w${DateTime.now().millisecondsSinceEpoch}',
          type: spec.type,
          x: spot.x,
          y: spot.y,
          w: size.w,
          h: size.h,
        );
        _update(layout.copyWith(widgets: [...layout.widgets, item]));
        setState(() => _selectedId = item.id);
        if (spec.hasOptions) await _editGridOptions(item);
        return;
      }
    }
    _snack('빈자리가 없어요. 다른 위젯을 보관함으로 끌어 놓거나 작게 줄인 뒤 다시 넣어 주세요.');
  }

  /// 다른 위젯 위에 놓아서 자리 바꾸기
  void _swapWidgets(List<GridItem> widgets, String message) {
    _update(_layout!.copyWith(widgets: widgets));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(label: '실행 취소', onPressed: _undo),
      ));
  }

  bool _isOverParking(Offset global) {
    final box = _parkingKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    // 띠 테두리에 딱 맞추지 않아도 되게 위·옆으로 넉넉히 (아래는 화면 끝까지)
    final r = box.localToGlobal(Offset.zero) & box.size;
    var top = r.top - 24;
    // 좁은 화면: 보관함이 스크롤 영역 안에 있음 → 화면에 보일 때만, 스크롤 영역 위(미리보기)로는 안 넘어가게
    final scrollBox = _narrowScrollKey.currentContext?.findRenderObject() as RenderBox?;
    if (scrollBox != null && scrollBox.hasSize) {
      final view = scrollBox.localToGlobal(Offset.zero) & scrollBox.size;
      if (r.bottom <= view.top || r.top >= view.bottom) return false;
      top = math.max(top, view.top);
    }
    return Rect.fromLTRB(r.left - 32, top, r.right + 32, double.infinity).contains(global);
  }

  /// 미리보기에서 위젯을 끌기 시작/끝. 좁은 화면에서는 보관함이 보이게 스크롤을 맨 위로
  void _onMoveDragChanged(bool moving) {
    setState(() => _movingWidget = moving);
    if (moving && _narrowScroll.hasClients && _narrowScroll.offset > 0) {
      _narrowScroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  /// 격자에서 보관함으로 (설정은 그대로). 직원 호출처럼 꼭 있어야 하는 위젯도 잠깐은 뺄 수 있고, 저장할 때 검사함
  void _park(GridItem item) {
    final layout = _layout!;
    _update(layout.copyWith(
      widgets: layout.widgets.where((w) => w.id != item.id).toList(),
      parked: [...layout.parked, item],
    ));
    if (_selectedId == item.id) setState(() => _selectedId = null);
    _snack('${specOf(item.type)?.name ?? '위젯'}을(를) 보관함에 넣었어요. 빈 칸이 생겼어요.');
  }

  /// 보관함에서 격자로 (끌어 놓은 자리)
  void _unpark(GridItem placed) {
    final layout = _layout!;
    final problem = layout.problemFor(placed);
    if (problem != null) {
      _warn(problem);
      return;
    }
    _update(layout.copyWith(
      widgets: [...layout.widgets, placed],
      parked: layout.parked.where((p) => p.id != placed.id).toList(),
    ));
    setState(() => _selectedId = placed.id);
  }

  /// 보관함에서 '넣기' 버튼: 들어갈 수 있는 첫 빈자리에
  void _unparkAuto(GridItem item) {
    final layout = _layout!;
    final spec = specOf(item.type);
    for (final size in [WidgetSize(item.w, item.h), ...?spec?.sizes]) {
      final spot = layout.findSpot(size.w, size.h);
      if (spot != null) {
        _unpark(item.copyWith(x: spot.x, y: spot.y, w: size.w, h: size.h));
        return;
      }
    }
    _warn('빈자리가 없어요. 다른 위젯을 보관함으로 옮긴 뒤 다시 넣어 주세요.');
  }

  void _deleteParked(GridItem item) {
    final layout = _layout!;
    _update(layout.copyWith(parked: layout.parked.where((p) => p.id != item.id).toList()));
  }

  /// 위치·크기 바꾸기 (겹치거나 허용 안 되는 크기면 경고만)
  bool _replaceItem(GridItem next) {
    final layout = _layout!;
    final problem = layout.problemFor(next);
    if (problem != null) {
      _warn(problem);
      return false;
    }
    _update(layout.copyWith(widgets: [for (final w in layout.widgets) w.id == next.id ? next : w]));
    return true;
  }

  void _removeItem(GridItem item) {
    final layout = _layout!;
    if (_tryUpdate(layout.copyWith(widgets: layout.widgets.where((w) => w.id != item.id).toList()))) {
      if (_selectedId == item.id) setState(() => _selectedId = null);
    }
  }

  void _resize(GridItem item, WidgetSize size) {
    final spec = specOf(item.type)!;
    if (!spec.sizes.contains(size)) {
      _warn('${spec.name}은(는) ${size.label} 크기를 쓸 수 없어요. (가능: ${spec.sizes.map((s) => s.label).join(', ')})');
      return;
    }
    // 오른쪽·아래로 넘치면 안쪽으로 당겨서 시도
    final cols = _layout!.cols;
    final x = item.x + size.w > cols ? cols - size.w : item.x;
    final y = item.y + size.h > HomeLayout.rows ? HomeLayout.rows - size.h : item.y;
    _replaceItem(item.copyWith(w: size.w, h: size.h, x: x < 0 ? 0 : x, y: y < 0 ? 0 : y));
  }

  Future<void> _editGridOptions(GridItem item) async {
    final result = await _showOptionsDialog(item.type, item.options);
    if (result != null) {
      final current = _layout!.widgets.where((w) => w.id == item.id);
      if (current.isNotEmpty) {
        final next = current.first.copyWith(options: result);
        _update(_layout!.copyWith(widgets: [for (final w in _layout!.widgets) w.id == next.id ? next : w]));
      }
    }
  }

  // ── 왼쪽 영역 편집 ──

  void _addSidebarItem(String type) {
    final layout = _layout!;
    _tryUpdate(layout.copyWith(sidebarItems: [...layout.sidebarItems, SidebarItem(type)]));
  }

  void _removeSidebarItem(int index) {
    final layout = _layout!;
    final items = [...layout.sidebarItems]..removeAt(index);
    _tryUpdate(layout.copyWith(sidebarItems: items));
  }

  void _reorderSidebar(int oldIndex, int newIndex) {
    final layout = _layout!;
    final items = [...layout.sidebarItems];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    _update(layout.copyWith(sidebarItems: items));
  }

  Future<void> _editSidebarOptions(int index) async {
    final item = _layout!.sidebarItems[index];
    final result = await _showOptionsDialog(item.type, item.options, sidebar: true);
    if (result != null) {
      final items = [..._layout!.sidebarItems];
      items[index] = item.copyWith(options: result);
      _tryUpdate(_layout!.copyWith(sidebarItems: items));
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
      },
      child: Focus(autofocus: true, child: _buildScaffold(context)),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Row(
        children: [
          AdminSidebar(currentScreen: 'home', onNavigate: _navigate),
          Expanded(
            child: _layout == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < _stackBelow) return _buildNarrowBody(constraints);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 12),
                            _buildErrors(),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildPreview()),
                                  const SizedBox(width: 24),
                                  SizedBox(width: 420, child: _buildPanel()),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 좁은 화면(폰·아이패드 세로): 머리줄·미리보기는 위에 고정, 보관함·위젯 목록은 아래에서 스크롤.
  /// 미리보기를 스크롤 밖에 둬야 위젯을 위아래로 끌 때 화면이 같이 스크롤되지 않음
  Widget _buildNarrowBody(BoxConstraints constraints) {
    final previewMaxHeight = (constraints.maxHeight * 0.38).clamp(120.0, 460.0).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(compact: true),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: previewMaxHeight),
            child: Center(heightFactor: 1, child: _previewFrame(bezel: 8)),
          ),
          Expanded(
            child: SingleChildScrollView(
              key: _narrowScrollKey,
              controller: _narrowScroll,
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildErrors(),
                  if (_tab == 0) ...[
                    _buildParkingTray(),
                    const SizedBox(height: 12),
                  ],
                  _previewHint(below: true),
                  const SizedBox(height: 12),
                  _buildPanel(compact: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({bool compact = false}) {
    final errors = _layout!.validate();
    // 한 줄에 다 들어가면 제목 왼쪽·버튼 오른쪽, 좁으면 버튼이 아래 줄로 내려감
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('홈 화면 꾸미기', style: TextStyle(fontSize: compact ? 24 : 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            const Text('저장하면 매장의 모든 손님 패드에 바로 적용돼요', style: TextStyle(color: Colors.black54)),
          ],
        ),
        Wrap(
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_dirty)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text('저장하지 않은 변경 사항이 있어요', style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
              ),
            ..._headerButtons(errors),
          ],
        ),
      ],
    );
  }

  List<Widget> _headerButtons(List<String> errors) {
    return [
      Tooltip(
        message: '방금 한 변경 되돌리기 (Ctrl+Z)',
        // 아이콘 없이 글자만 가운데 (아이콘 자리가 비어 보여서 글자가 한쪽으로 쏠려 보였음)
        child: OutlinedButton(
          onPressed: _history.isEmpty ? null : _undo,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            foregroundColor: _adminNavy,
            disabledForegroundColor: Colors.black38,
            side: BorderSide(color: _history.isEmpty ? const Color(0xFFDDDDDD) : const Color(0xFF8A94A3)),
          ),
          child: const Text('실행 취소', textAlign: TextAlign.center),
        ),
      ),
      OutlinedButton.icon(
        onPressed: _pickPreset,
        icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
        label: const Text('예시 배치 고르기'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
      ),
      TextButton(onPressed: _resetToDefault, child: const Text('기본 배치로 되돌리기')),
      FilledButton.icon(
        onPressed: (_saving || errors.isNotEmpty || !_dirty) ? null : _save,
        icon: _saving
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_outlined),
        label: const Text('저장하고 매장에 적용', style: TextStyle(fontWeight: FontWeight.bold)),
        style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size(0, 46)),
      ),
    ];
  }

  Widget _buildErrors() {
    final errors = _layout!.validate();
    if (errors.isEmpty) return const SizedBox(height: 4);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFFFF1EC), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in errors.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFB33A2A), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e, style: const TextStyle(color: Color(0xFF8A2A1E)))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    // 스크롤 안에 두면 위아래로 끌 때 화면이 스크롤돼서, 남는 공간에 맞춰 줄여서 보여 줌
    return Column(
      children: [
        Flexible(child: Center(child: _previewFrame())),
        if (_tab == 0) ...[
          const SizedBox(height: 12),
          _buildParkingTray(),
        ],
        const SizedBox(height: 12),
        _previewHint(),
      ],
    );
  }

  /// 손님 패드 모양 테두리 + 실제 홈 화면 + 끌어 옮기기 층 (넓은·좁은 화면 공용)
  Widget _previewFrame({double bezel = 14}) {
    return Container(
      padding: EdgeInsets.all(bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B18),
        borderRadius: BorderRadius.circular(bezel + 16),
        boxShadow: const [BoxShadow(color: Color(0x40281E14), blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: HomeLayout.designWidth / HomeLayout.designHeight,
          child: FittedBox(
            child: SizedBox(
              width: HomeLayout.designWidth,
              height: HomeLayout.designHeight,
              child: Stack(
                children: [
                  AbsorbPointer(
                    child: HomeView(
                      layout: _layout!,
                      roomNumber: 7,
                      highlightSidebar: _tab == 1,
                    ),
                  ),
                  if (_tab == 0)
                    Positioned.fill(
                      child: GridEditOverlay(
                        layout: _layout!,
                        selectedId: _selectedId,
                        onSelect: (id) => setState(() => _selectedId = id),
                        onCommit: _replaceItem,
                        onSwap: _swapWidgets,
                        onReject: _warn,
                        isOverParking: _isOverParking,
                        onParkingHover: (over) => setState(() => _parkingHover = over),
                        onPark: _park,
                        onUnpark: _unpark,
                        onMoveDragChanged: _onMoveDragChanged,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// below: 좁은 화면 (목록이 미리보기 아래에 있음)
  Widget _previewHint({bool below = false}) {
    return Text(
      _tab == 0
          ? below
              ? '위젯을 끌어서 옮기고, 다른 위젯 위에 놓으면 자리가 바뀌어요. 미리보기가 작을 때는 아래 목록의 크기·열·행으로 바꾸면 편해요. 미리보기는 7번 룸 기준이에요.'
              : '위젯을 끌어서 옮기고, 다른 위젯 위에 놓으면 자리가 바뀌어요. 선택한 위젯의 오른쪽 아래 손잡이로 크기를 바꿔요. 미리보기는 7번 룸 기준이에요.'
          : '왼쪽 영역은 ${below ? '아래' : '오른쪽'} 목록에서 순서를 바꾸고, 로고 설정에서 사진과 매장 이름을 바꿔요.',
      style: TextStyle(color: Colors.black.withValues(alpha: 0.5), fontSize: 13),
    );
  }

  /// 보관함 띠: 위젯을 끌어 놓으면 잠깐 빼 두고, 칩을 미리보기로 끌거나 '넣기'로 다시 넣음.
  /// 미리보기에서 위젯을 끄는 동안에는 크게 펼쳐서 놓을 곳을 분명하게 보여 줌
  Widget _buildParkingTray() {
    final parked = _layout!.parked;
    final hover = _parkingHover;
    final moving = _movingWidget;
    final active = moving || hover;
    return AnimatedContainer(
      key: _parkingKey,
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: BoxDecoration(
        color: hover
            ? const Color(0xFFFFE3CC)
            : moving
                ? const Color(0xFFFFF4EA)
                : Colors.white,
        borderRadius: BorderRadius.circular(14),
        // 테두리 두께는 그대로 (두께가 바뀌면 미리보기 크기가 같이 흔들림)
        border: Border.all(color: active ? _accent : const Color(0xFFDCD6CE), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 제목 줄: 아이콘 · 보관함 N개 ······ 짧은 설명
          Row(
            children: [
              Icon(Icons.archive_outlined, size: 20, color: active ? _accent : _adminNavy),
              const SizedBox(width: 8),
              Text(
                parked.isEmpty ? '보관함' : '보관함 · ${parked.length}개',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: active ? _accent : null),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('손님 화면에는 안 보이고, 설정은 그대로 남아요',
                    textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: Colors.black45)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 높이가 바뀌면 미리보기가 줄었다 늘었다 해서, 끄는 중 표시는 내용 위에 겹쳐서 보여 줌
          Stack(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: parked.isEmpty
                    ? Container(
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7F8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: const Text(
                          '미리보기의 위젯을 여기로 끌어 놓으면 빈 칸을 만들 수 있어요',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.black45),
                        ),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final item in parked) _parkedChip(item)],
                        ),
                      ),
              ),
              if (active)
                Positioned.fill(child: _parkingDropZone(hover)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _parkingDropZone(bool hover) {
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hover ? const Color(0xFFFFD9BC) : const Color(0xFFFFF4EA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _accent.withValues(alpha: hover ? 0.9 : 0.4), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hover ? Icons.check_circle : Icons.move_to_inbox, color: _accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                hover ? '놓으면 보관함에 들어가요' : '여기로 끌어 놓으면 잠깐 빼 둘 수 있어요',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parkedChip(GridItem item) {
    final spec = specOf(item.type);
    final name = spec?.name ?? item.type;
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2DAD0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.drag_indicator, size: 16, color: Colors.black38),
          const SizedBox(width: 2),
          Icon(spec?.icon ?? Icons.widgets_outlined, size: 18, color: _adminNavy),
          const SizedBox(width: 6),
          Flexible(
            child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          Text(WidgetSize(item.w, item.h).label, style: const TextStyle(fontSize: 12, color: Colors.black45)),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => _unparkAuto(item),
            style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('넣기'),
          ),
          IconButton(
            tooltip: '완전히 삭제',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18, color: Color(0xFFB33A2A)),
            onPressed: () => _deleteParked(item),
          ),
        ],
      ),
    );
    return Draggable<String>(
      data: item.id,
      // 손가락 위치 = 놓는 위치 (미리보기에서 칸 계산에 씀)
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: const Offset(-20, -20),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(spec?.icon ?? Icons.widgets_outlined, size: 18, color: _accent),
                const SizedBox(width: 6),
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: chip),
    );
  }

  /// compact: 좁은 화면 스크롤 안에 넣을 때 (목록을 다 펼쳐서 바깥 스크롤 하나로)
  Widget _buildPanel({bool compact = false}) {
    final body = _tab == 0 ? _buildGridPanel(compact: compact) : _buildSidebarPanel(compact: compact);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('격자 위젯'), icon: Icon(Icons.grid_view)),
              ButtonSegment(value: 1, label: Text('왼쪽 영역'), icon: Icon(Icons.view_sidebar_outlined)),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 16),
          if (compact) body else Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildGridPanel({bool compact = false}) {
    final layout = _layout!;
    final items = [...layout.widgets]..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    return Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('위젯 ${items.length}개 · ${layout.cols}×${HomeLayout.rows}칸',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            FilledButton.icon(
              onPressed: _addWidget,
              icon: const Icon(Icons.add),
              label: const Text('위젯 추가'),
              style: FilledButton.styleFrom(backgroundColor: _adminNavy),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('미리보기에서 위젯을 끌어 옮기고, 오른쪽 아래 손잡이로 크기를 바꿀 수 있어요.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 12),
        if (compact)
          ...[
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _gridItemTile(items[i]),
            ],
          ]
        else
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _gridItemTile(items[i]),
            ),
          ),
      ],
    );
  }

  Widget _gridItemTile(GridItem item) {
    final spec = specOf(item.type)!;
    final layout = _layout!;
    final selected = item.id == _selectedId;
    final maxX = layout.cols - item.w;
    final maxY = HomeLayout.rows - item.h;
    return Material(
      color: selected ? const Color(0xFFFFF4EA) : const Color(0xFFF7F7F8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? _accent : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedId = item.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(spec.icon, size: 20, color: _adminNavy),
                  const SizedBox(width: 8),
                  Expanded(child: Text(spec.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (spec.hasOptions)
                    IconButton(
                      tooltip: '설정',
                      icon: const Icon(Icons.tune, size: 20),
                      onPressed: () => _editGridOptions(item),
                    ),
                  Tooltip(
                    message: '잠깐 빼 두기 (설정 유지)',
                    child: TextButton.icon(
                      onPressed: () => _park(item),
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      label: const Text('보관'),
                      style: TextButton.styleFrom(
                        foregroundColor: _adminNavy,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '빼기',
                    icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFB33A2A)),
                    onPressed: () => _removeItem(item),
                  ),
                ],
              ),
              // 좁으면 크기·열·행이 다음 줄로 내려감
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _miniDropdown<WidgetSize>(
                    label: '크기',
                    value: WidgetSize(item.w, item.h),
                    items: allGridSizes,
                    text: (s) => s.label,
                    enabled: (s) => spec.sizes.contains(s),
                    onChanged: (s) => _resize(item, s),
                  ),
                  _miniDropdown<int>(
                    label: '열',
                    value: item.x.clamp(0, maxX < 0 ? 0 : maxX).toInt(),
                    items: [for (var x = 0; x <= (maxX < 0 ? 0 : maxX); x++) x],
                    text: (x) => '${x + 1}',
                    onChanged: (x) => _replaceItem(item.copyWith(x: x)),
                  ),
                  _miniDropdown<int>(
                    label: '행',
                    value: item.y.clamp(0, maxY < 0 ? 0 : maxY).toInt(),
                    items: [for (var y = 0; y <= (maxY < 0 ? 0 : maxY); y++) y],
                    text: (y) => '${y + 1}',
                    onChanged: (y) => _replaceItem(item.copyWith(y: y)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) text,
    required void Function(T) onChanged,
    bool Function(T)? enabled,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(width: 6),
        DropdownButton<T>(
          value: items.contains(value) ? value : items.first,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i,
                child: Text(
                  text(i),
                  style: TextStyle(
                    color: (enabled == null || enabled(i)) ? Colors.black87 : Colors.black26,
                    decoration: (enabled == null || enabled(i)) ? null : TextDecoration.lineThrough,
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }

  Widget _buildSidebarPanel({bool compact = false}) {
    final layout = _layout!;
    final present = layout.sidebarItems.map((e) => e.type).toSet();
    final addable = sidebarCatalog.where((s) => s.type == 'spacer' || !present.contains(s.type)).toList();
    return Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('왼쪽 영역 보이기', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('끄면 격자가 7×4칸이 돼요. 직원 호출을 격자에 넣어야 저장돼요.', style: TextStyle(fontSize: 12)),
          value: layout.sidebarVisible,
          onChanged: (v) => _tryUpdate(layout.copyWith(sidebarVisible: v)),
        ),
        if (layout.sidebarVisible) ...[
          const SizedBox(height: 8),
          const Text('배경색', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final c in sidebarColors)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _update(layout.copyWith(sidebarColor: c)),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c.toARGB32() == layout.sidebarColor.toARGB32() ? _accent : Colors.black12,
                          width: c.toARGB32() == layout.sidebarColor.toARGB32() ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text('들어 있는 요소 (끌어서 순서 바꾸기)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              PopupMenuButton<String>(
                tooltip: '요소 추가',
                onSelected: _addSidebarItem,
                itemBuilder: (_) => [
                  for (final s in addable)
                    PopupMenuItem(
                      value: s.type,
                      child: Row(children: [Icon(s.icon, size: 18), const SizedBox(width: 8), Text(s.name)]),
                    ),
                ],
                child: const Chip(avatar: Icon(Icons.add, size: 18), label: Text('요소 추가')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _expandUnless(
            compact,
            ReorderableListView.builder(
              buildDefaultDragHandles: false,
              // 좁은 화면: 바깥 스크롤 하나로 (목록은 다 펼침)
              shrinkWrap: compact,
              physics: compact ? const NeverScrollableScrollPhysics() : null,
              itemCount: layout.sidebarItems.length,
              onReorder: _reorderSidebar,
              itemBuilder: (context, i) {
                final item = layout.sidebarItems[i];
                final spec = sidebarSpecOf(item.type)!;
                return Padding(
                  key: ValueKey('side-$i-${item.type}'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: const Color(0xFFF7F7F8),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      dense: true,
                      // 좁은 화면: 양옆 여백·간격을 줄여서 이름 자리를 넓힘
                      contentPadding: compact ? const EdgeInsets.only(left: 8, right: 4) : null,
                      horizontalTitleGap: compact ? 8 : null,
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_indicator, color: Colors.black38),
                      ),
                      title: Row(
                        children: [
                          Icon(spec.icon, size: 18, color: _adminNavy),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(spec.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      subtitle: spec.locked
                          ? const Text('빠르게 10번 눌러 로그아웃 기능이 있어 뺄 수 없어요', style: TextStyle(fontSize: 11))
                          : item.type == 'staffCall'
                              ? const Text('빼려면 격자에 직원 호출 위젯이 있어야 해요', style: TextStyle(fontSize: 11))
                              : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (spec.hasOptions)
                            IconButton(
                              tooltip: '설정',
                              visualDensity: compact ? VisualDensity.compact : null,
                              icon: const Icon(Icons.tune, size: 20),
                              onPressed: () => _editSidebarOptions(i),
                            ),
                          if (spec.locked)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.lock_outline, size: 20, color: Colors.black38),
                            )
                          else
                            IconButton(
                              tooltip: '빼기',
                              visualDensity: compact ? VisualDensity.compact : null,
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => _removeSidebarItem(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ] else
          _expandUnless(
            compact,
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('왼쪽 영역이 꺼져 있어요.\n로그아웃은 화면 왼쪽 위 구석을 빠르게 10번 누른 뒤 패드 비밀번호(또는 PIN)를 넣으면 돼요.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              ),
            ),
          ),
      ],
    );
  }

  /// 넓은 화면은 남는 높이를 채우고(Expanded), 좁은 화면(스크롤 안)은 내용 높이만큼
  Widget _expandUnless(bool compact, Widget child) => compact ? child : Expanded(child: child);

  // ── 위젯·요소 설정 창 ──

  Future<Map<String, dynamic>?> _showOptionsDialog(String type, Map<String, dynamic> current,
      {bool sidebar = false}) {
    final o = Map<String, dynamic>.from(current);
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final title = sidebar ? (sidebarSpecOf(type)?.name ?? type) : (specOf(type)?.name ?? type);

    switch (type) {
      case 'wifi':
        c1.text = (o['ssid'] ?? '').toString();
        c2.text = (o['password'] ?? '').toString();
        break;
      case 'qr':
        c1.text = (o['url'] ?? '').toString();
        c2.text = (o['label'] ?? '리뷰 남기기').toString();
        break;
      case 'memo':
      case 'note':
        c1.text = (o['text'] ?? '').toString();
        break;
      case 'greeting':
        c1.text = (o['small'] ?? '').toString();
        c2.text = (o['text'] ?? '').toString();
        break;
      case 'banner':
        c1.text = (o['caption'] ?? '').toString();
        break;
      case 'logo':
        c1.text = (o['name'] ?? '').toString();
        break;
      case 'timer':
        c1.text = (o['minutes'] ?? 5).toString();
        break;
      case 'fee':
        final rows = o['rows'] is List ? o['rows'] as List : const [];
        c1.text = rows.whereType<Map>().map((r) => '${r['label'] ?? ''} | ${r['value'] ?? ''}').join('\n');
        break;
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          Widget body;
          switch (type) {
            case 'wifi':
              body = Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: c1, decoration: const InputDecoration(labelText: '와이파이 이름')),
                const SizedBox(height: 12),
                TextField(controller: c2, decoration: const InputDecoration(labelText: '비밀번호')),
              ]);
              break;
            case 'qr':
              body = Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: c1,
                    decoration: const InputDecoration(labelText: 'QR로 열 주소', hintText: 'https://...')),
                const SizedBox(height: 12),
                TextField(controller: c2, decoration: const InputDecoration(labelText: 'QR 아래 문구')),
              ]);
              break;
            case 'memo':
            case 'note':
              body = TextField(
                controller: c1,
                maxLines: 3,
                maxLength: type == 'note' ? 40 : 60,
                decoration: const InputDecoration(labelText: '보여줄 문구', hintText: '예: 주말에는 1인 1음료 부탁드려요'),
              );
              break;
            case 'greeting':
              body = Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: c1,
                  maxLength: 20,
                  decoration: const InputDecoration(labelText: '작은 줄 (선택)', hintText: '안녕하세요!'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: c2,
                  maxLength: 30,
                  decoration: const InputDecoration(labelText: '큰 줄', hintText: '오늘도 즐거운 게임 시간 보내세요'),
                ),
              ]);
              break;
            case 'timer':
              body = TextField(
                controller: c1,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '기본 시간 (분)', hintText: '5'),
              );
              break;
            case 'fee':
              body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('한 줄에 하나씩 "항목 | 금액"으로 적어 주세요. (최대 4줄)',
                    style: TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 8),
                TextField(
                  controller: c1,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '시간제 | 1시간 2,400원\n추가 10분 | 400원\n무제한 | 8,000원',
                  ),
                ),
              ]);
              break;
            case 'links':
              final selected = (o['targets'] is List)
                  ? (o['targets'] as List).map((e) => e.toString()).toList()
                  : <String>['event', 'tools', 'notice'];
              body = Column(mainAxisSize: MainAxisSize.min, children: [
                for (final e in linkTargets.entries)
                  CheckboxListTile(
                    value: selected.contains(e.key),
                    title: Text(e.value),
                    // 84차: 결제가 끝나면 비워지는 목록이라 토스 POS 연동 매장에서만 손님 화면에 보임
                    subtitle: e.key == 'orders' ? const Text('토스 POS 연동 매장에서만 손님 화면에 보여요') : null,
                    onChanged: (v) => setDlg(() {
                      if (v == true) {
                        if (selected.length < 5) selected.add(e.key);
                      } else {
                        selected.remove(e.key);
                      }
                      o['targets'] = [...selected];
                    }),
                  ),
              ]);
              break;
            case 'menuPick':
              body = _MenuSelector(
                selectedId: o['menuId']?.toString(),
                onChanged: (id) => setDlg(() => o['menuId'] = id),
              );
              break;
            case 'aiPick':
              final count = (o['count'] is num) ? (o['count'] as num).toInt() : 3;
              final exclude = (o['exclude'] is List) ? (o['exclude'] as List).map((e) => e.toString()).toList() : <String>[];
              body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('추천 개수', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 2, label: Text('2개')),
                    ButtonSegment(value: 3, label: Text('3개')),
                    ButtonSegment(value: 4, label: Text('4개')),
                  ],
                  selected: {count.clamp(2, 4).toInt()},
                  onSelectionChanged: (s) => setDlg(() => o['count'] = s.first),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('맞춤 추천 버튼 보이기'),
                  subtitle: const Text('손님이 인원·분위기를 골라 다시 추천받아요'),
                  value: o['showAsk'] != false,
                  onChanged: (v) => setDlg(() => o['showAsk'] = v),
                ),
                const SizedBox(height: 8),
                Text('추천에서 뺄 게임 (${exclude.length}개)', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('부품이 빠진 게임 등은 여기서 빼 주세요. 대여 불가 게임은 원래 추천되지 않아요.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: _GameExcludeList(
                    excluded: exclude,
                    onChanged: (list) => setDlg(() => o['exclude'] = list),
                  ),
                ),
              ]);
              break;
            case 'logo':
              body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('로고 사진', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Center(
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: _ImageUploadBox(
                      imageUrl: o['imageUrl']?.toString(),
                      folder: 'home_logo',
                      circle: true,
                      emptyText: '눌러서 로고 올리기',
                      onImage: (url) => setDlg(() => o['imageUrl'] = url),
                    ),
                  ),
                ),
                if (o['imageUrl'] != null && o['imageUrl'].toString().isNotEmpty)
                  Center(
                    child: TextButton(
                      onPressed: () => setDlg(() => o.remove('imageUrl')),
                      child: const Text('로고 지우기 (로고 없이 표시)'),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: c1,
                  maxLength: 14,
                  decoration: const InputDecoration(labelText: '매장 이름', hintText: '비워 두면 이름 없이 표시'),
                ),
                const Text('정사각형 사진이 가장 잘 맞아요. 동그랗게 잘려서 보여요.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ]);
              break;
            case 'banner':
              body = _BannerOptions(
                imageUrl: o['imageUrl']?.toString(),
                link: o['link']?.toString() ?? 'none',
                captionController: c1,
                onImage: (url) => setDlg(() => o['imageUrl'] = url),
                onLink: (link) => setDlg(() => o['link'] = link),
              );
              break;
            default:
              body = const Text('설정할 것이 없어요.');
          }

          return AlertDialog(
            title: Text('$title 설정', style: const TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(width: adminDialogWidth(ctx, 460), child: SingleChildScrollView(child: body)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
              FilledButton(
                onPressed: () {
                  switch (type) {
                    case 'wifi':
                      o['ssid'] = c1.text.trim();
                      o['password'] = c2.text.trim();
                      break;
                    case 'qr':
                      o['url'] = c1.text.trim();
                      o['label'] = c2.text.trim();
                      break;
                    case 'memo':
                    case 'note':
                      o['text'] = c1.text.trim();
                      break;
                    case 'greeting':
                      o['small'] = c1.text.trim();
                      o['text'] = c2.text.trim();
                      break;
                    case 'banner':
                      o['caption'] = c1.text.trim();
                      break;
                    case 'logo':
                      o['name'] = c1.text.trim();
                      break;
                    case 'timer':
                      o['minutes'] = (int.tryParse(c1.text.trim()) ?? 5).clamp(1, 99);
                      break;
                    case 'fee':
                      o['rows'] = c1.text
                          .split('\n')
                          .map((line) => line.split('|'))
                          .where((p) => p.first.trim().isNotEmpty)
                          .take(4)
                          .map((p) => {'label': p.first.trim(), 'value': p.length > 1 ? p.sublist(1).join('|').trim() : ''})
                          .toList();
                      break;
                  }
                  Navigator.pop(ctx, o);
                },
                child: const Text('적용'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 위젯 추가 창 (분류별 목록)
class _WidgetPickerDialog extends StatelessWidget {
  final Set<String> placedTypes;
  final Set<String> parkedTypes;
  const _WidgetPickerDialog({required this.placedTypes, this.parkedTypes = const {}});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('위젯 추가', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: adminDialogWidth(context, 560),
        // 낮은 화면(폰 가로 등)에서는 제목·버튼 자리를 빼고 남는 만큼만
        height: math.max(200.0, math.min(560.0, MediaQuery.sizeOf(context).height - 240)),
        child: ListView(
          children: [
            for (final cat in WidgetCategory.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text(widgetCategoryNames[cat]!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              for (final spec in widgetCatalog.where((s) => s.category == cat && specOf(s.type) != null))
                ListTile(
                  leading: Icon(spec.icon, color: _adminNavy),
                  title: Text(spec.name),
                  subtitle: Text('${spec.description} · ${spec.sizes.map((s) => s.label).join(', ')}'),
                  trailing: placedTypes.contains(spec.type)
                      ? const Text('배치됨', style: TextStyle(color: Colors.black45, fontSize: 12))
                      : parkedTypes.contains(spec.type)
                          ? const Text('보관함에 있음', style: TextStyle(color: Colors.black45, fontSize: 12))
                          : const Icon(Icons.add_circle_outline),
                  onTap: () => Navigator.pop(context, spec),
                ),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
    );
  }
}

/// 오늘의 추천 메뉴 고르기
class _MenuSelector extends StatefulWidget {
  final String? selectedId;
  final void Function(String id) onChanged;
  const _MenuSelector({required this.selectedId, required this.onChanged});

  @override
  State<_MenuSelector> createState() => _MenuSelectorState();
}

class _MenuSelectorState extends State<_MenuSelector> {
  late final Future<QuerySnapshot<Map<String, dynamic>>> _menus =
      StoreScope.col('menus').get().metered();

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.selectedId;
    final onChanged = widget.onChanged;
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _menus,
      builder: (context, snap) {
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Text('등록된 메뉴가 없어요.');
        return SizedBox(
          height: 360,
          child: ListView(
            children: [
              for (final d in docs)
                ListTile(
                  leading: Icon(
                    d.id == selectedId ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: d.id == selectedId ? _accent : Colors.black38,
                  ),
                  title: Text((d.data()['name'] ?? '').toString()),
                  subtitle: Text('${d.data()['price'] ?? ''}원'),
                  onTap: () => onChanged(d.id),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// AI 추천에서 뺄 게임 고르기
class _GameExcludeList extends StatefulWidget {
  final List<String> excluded;
  final void Function(List<String>) onChanged;
  const _GameExcludeList({required this.excluded, required this.onChanged});

  @override
  State<_GameExcludeList> createState() => _GameExcludeListState();
}

class _GameExcludeListState extends State<_GameExcludeList> {
  late final Future<QuerySnapshot<Map<String, dynamic>>> _games =
      StoreScope.col('games').where('isAvailable', isEqualTo: true).get().metered();

  @override
  Widget build(BuildContext context) {
    final excluded = widget.excluded;
    final onChanged = widget.onChanged;
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _games,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = [...snap.data!.docs]
          ..sort((a, b) => (a.data()['title'] ?? '').toString().compareTo((b.data()['title'] ?? '').toString()));
        return ListView(
          children: [
            for (final d in docs)
              CheckboxListTile(
                dense: true,
                value: excluded.contains(d.id),
                title: Text((d.data()['title'] ?? '').toString()),
                onChanged: (v) {
                  final next = [...excluded];
                  if (v == true) {
                    next.add(d.id);
                  } else {
                    next.remove(d.id);
                  }
                  onChanged(next);
                },
              ),
          ],
        );
      },
    );
  }
}

/// 사진 올리기 상자 (Firebase Storage에 올리고 주소를 돌려줌)
class _ImageUploadBox extends StatefulWidget {
  final String? imageUrl;
  final String folder;
  final bool circle;
  final String emptyText;
  final void Function(String url) onImage;

  const _ImageUploadBox({
    required this.imageUrl,
    required this.folder,
    required this.onImage,
    this.circle = false,
    this.emptyText = '눌러서 사진 올리기',
  });

  @override
  State<_ImageUploadBox> createState() => _ImageUploadBoxState();
}

class _ImageUploadBoxState extends State<_ImageUploadBox> {
  bool _uploading = false;

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final ref = StoreScope.storage.child('${widget.folder}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      final task = await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      widget.onImage(await task.ref.getDownloadURL());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('사진을 올리지 못했어요. ($e)')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F1F3),
      shape: widget.circle ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _uploading ? null : _pick,
        child: _uploading
            ? const Center(child: CircularProgressIndicator())
            : hasValidImage(widget.imageUrl)
                ? AppNetworkImage(imageUrl: widget.imageUrl!, fit: BoxFit.cover)
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_photo_alternate_outlined, size: 36, color: Colors.black45),
                      const SizedBox(height: 6),
                      Text(widget.emptyText,
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                    ]),
                  ),
      ),
    );
  }
}

/// 사진 배너 설정 (사진 올리기 + 문구 + 누르면 갈 곳)
class _BannerOptions extends StatelessWidget {
  final String? imageUrl;
  final String link;
  final TextEditingController captionController;
  final void Function(String url) onImage;
  final void Function(String link) onLink;

  const _BannerOptions({
    required this.imageUrl,
    required this.link,
    required this.captionController,
    required this.onImage,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 2,
          child: _ImageUploadBox(imageUrl: imageUrl, folder: 'home_banners', onImage: onImage),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: captionController,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '사진 위 문구 (없어도 돼요)'),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: link,
          decoration: const InputDecoration(labelText: '누르면 갈 곳'),
          items: [
            const DropdownMenuItem(value: 'none', child: Text('없음')),
            for (final e in linkTargets.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => onLink(v ?? 'none'),
        ),
      ],
    );
  }
}
