import 'package:flutter/material.dart';

/// 손님 패드 홈 화면 배치 (Firestore settings/homeLayout)
///
/// 화면은 1280×800 기준으로 그린 뒤 기기 크기에 맞춰 통째로 늘리거나 줄입니다.
/// - 왼쪽 영역(sidebar): 위에서 아래로 쌓는 요소 목록
/// - 격자(grid): 왼쪽 영역이 있으면 6×4칸, 없으면 7×4칸. 위젯은 칸 단위 위치(x, y)와 크기(w, h)를 가짐

enum WidgetCategory { game, order, table, info, tools, decor }

const Map<WidgetCategory, String> widgetCategoryNames = {
  WidgetCategory.game: '게임',
  WidgetCategory.order: '주문',
  WidgetCategory.table: '테이블',
  WidgetCategory.info: '매장 정보',
  WidgetCategory.tools: '게임 도구',
  WidgetCategory.decor: '꾸미기',
};

class WidgetSize {
  final int w;
  final int h;
  const WidgetSize(this.w, this.h);

  /// 관리자 화면 표시용. 세로는 반 칸 단위라 예전 칸 기준으로 보여 줌 (예: 2×4 → "2×2", 2×1 → "2×0.5")
  String get label => '$w×${h.isEven ? '${h ~/ 2}' : (h / 2).toString()}';

  @override
  bool operator ==(Object other) => other is WidgetSize && other.w == w && other.h == h;

  @override
  int get hashCode => Object.hash(w, h);
}

/// 격자 위젯 종류 하나의 정보 (이름, 아이콘, 허용 크기)
class WidgetSpec {
  final String type;
  final String name;
  final String description;
  final IconData icon;
  final WidgetCategory category;
  final List<WidgetSize> sizes; // 첫 번째가 기본 크기
  final bool hasOptions; // 관리자 화면에서 설정할 게 있는지

  const WidgetSpec(
    this.type,
    this.name,
    this.description,
    this.icon,
    this.category,
    this.sizes, {
    this.hasOptions = false,
  });
}

/// AI 게임 추천(격자 위젯 '오늘의 추천 게임 (AI)' + 손님 맞춤 추천 팝업) 사용 여부.
/// 지금은 꺼 둠: 다른 앱에서 이미 AI 추천을 만들어서 패드에는 필요 없음. 코드는 남겨 둠.
/// false면 관리자 '홈 화면 꾸미기' 목록에 안 보이고, 저장된 배치에 있어도 손님 화면에 안 그려짐.
/// 다시 켜려면 true로 바꾸고 functions/index.js의 AI_ENABLED, firebase.json의 "/api/ai/**" 경로도 되살릴 것.
const bool kAiRecommendEnabled = false;

const List<WidgetSpec> widgetCatalog = [
  // 게임
  WidgetSpec('gameList', '게임 목록', '사진 카드 — 누르면 게임 목록', Icons.casino_outlined, WidgetCategory.game,
      [WidgetSize(2, 4), WidgetSize(3, 4), WidgetSize(2, 6), WidgetSize(2, 5), WidgetSize(3, 5), WidgetSize(3, 6)]),
  WidgetSpec('aiPick', '오늘의 추천 게임 (AI)', '매일 AI가 고른 게임 + 맞춤 추천', Icons.auto_awesome, WidgetCategory.game,
      [WidgetSize(2, 4), WidgetSize(3, 4), WidgetSize(2, 6)],
      hasOptions: true),
  WidgetSpec('search', '게임 검색', '게임 이름 검색창 (얇게 하면 검색창만)', Icons.search, WidgetCategory.game,
      [WidgetSize(2, 2), WidgetSize(3, 2), WidgetSize(2, 1), WidgetSize(3, 1)]),
  WidgetSpec('finder', '찾아보기', '인원별·장르별·난이도별 찾기 (얇게 하면 버튼만)', Icons.tune, WidgetCategory.game,
      [WidgetSize(2, 2), WidgetSize(3, 2), WidgetSize(3, 1), WidgetSize(4, 1)]),
  WidgetSpec('recommended', '추천 게임', '직원 추천 게임만 모아 보기', Icons.star_rounded, WidgetCategory.game,
      [WidgetSize(1, 2), WidgetSize(1, 1)]),
  // 주문
  WidgetSpec('foodOrder', '음식 주문', '사진 카드 — 누르면 주문 화면', Icons.restaurant, WidgetCategory.order,
      [WidgetSize(2, 4), WidgetSize(3, 4), WidgetSize(2, 6), WidgetSize(2, 5), WidgetSize(3, 5), WidgetSize(3, 6)]),
  WidgetSpec('menuPick', '오늘의 추천 메뉴', '고른 메뉴로 바로 주문', Icons.local_cafe_outlined, WidgetCategory.order,
      [WidgetSize(2, 2)],
      hasOptions: true),
  // 테이블
  WidgetSpec('clock', '시계', '현재 시각과 날짜', Icons.schedule, WidgetCategory.table,
      [WidgetSize(1, 2), WidgetSize(2, 2), WidgetSize(2, 1)]),
  WidgetSpec('room', '방 번호', '지금 이용 중인 방', Icons.meeting_room_outlined, WidgetCategory.table,
      [WidgetSize(1, 2), WidgetSize(2, 2), WidgetSize(2, 1)]),
  WidgetSpec('staffCall', '직원 호출', '직원 호출 버튼', Icons.notifications_active_outlined, WidgetCategory.table,
      [WidgetSize(1, 2), WidgetSize(2, 2), WidgetSize(2, 1)]),
  // 매장 정보
  WidgetSpec('notice', '공지사항', '가장 최근 공지 제목', Icons.campaign_outlined, WidgetCategory.info,
      [WidgetSize(2, 2), WidgetSize(2, 3), WidgetSize(2, 4)]),
  WidgetSpec('event', '이벤트', '진행 중인 이벤트', Icons.card_giftcard_outlined, WidgetCategory.info,
      [WidgetSize(2, 2), WidgetSize(1, 2), WidgetSize(2, 3), WidgetSize(2, 4)]),
  WidgetSpec('fee', '요금 안내', '요금표 (직접 입력)', Icons.payments_outlined, WidgetCategory.info, [WidgetSize(2, 2)],
      hasOptions: true),
  WidgetSpec('info', '이용안내', '이용안내 화면 바로가기', Icons.article_outlined, WidgetCategory.info, [WidgetSize(1, 2)]),
  WidgetSpec('wifi', '와이파이', '와이파이 이름·비밀번호', Icons.wifi, WidgetCategory.info, [WidgetSize(1, 2)],
      hasOptions: true),
  WidgetSpec('qr', '인스타·리뷰 QR', '링크를 QR로 보여주기', Icons.qr_code_2, WidgetCategory.info, [WidgetSize(1, 2)],
      hasOptions: true),
  // 게임 도구
  WidgetSpec('tools', '게임도구', '게임도구 화면 바로가기', Icons.timer_outlined, WidgetCategory.tools, [WidgetSize(1, 2)]),
  WidgetSpec('timer', '타이머', '홈에서 바로 쓰는 타이머', Icons.hourglass_bottom, WidgetCategory.tools, [WidgetSize(1, 2)],
      hasOptions: true),
  WidgetSpec('dice', '주사위', '눌러서 굴리기', Icons.casino, WidgetCategory.tools, [WidgetSize(1, 2)]),
  // 꾸미기
  WidgetSpec('banner', '사진 배너', '사진 + 문구, 누르면 원하는 화면으로', Icons.image_outlined, WidgetCategory.decor,
      [WidgetSize(2, 2), WidgetSize(4, 2)],
      hasOptions: true),
  WidgetSpec('greeting', '인사말', '배경 없이 크게 쓰는 인사 (작은 줄 + 큰 줄)', Icons.waving_hand_outlined, WidgetCategory.decor,
      [WidgetSize(4, 1), WidgetSize(3, 1), WidgetSize(2, 1), WidgetSize(4, 2), WidgetSize(3, 2), WidgetSize(2, 2)],
      hasOptions: true),
  WidgetSpec('memo', '자유 문구', '사장님이 쓰는 안내 문구', Icons.sticky_note_2_outlined, WidgetCategory.decor,
      [WidgetSize(2, 2)],
      hasOptions: true),
];

WidgetSpec? specOf(String type) {
  if (type == 'aiPick' && !kAiRecommendEnabled) return null; // AI 추천 꺼 둠 → 모르는 위젯처럼 취급
  for (final s in widgetCatalog) {
    if (s.type == type) return s;
  }
  return null;
}

/// 왼쪽 영역에 넣을 수 있는 요소
class SidebarSpec {
  final String type;
  final String name;
  final IconData icon;
  final double height; // 넘침 검사용 대략 높이 (빈 공간은 0)
  final bool locked; // 뺄 수 없음
  final bool hasOptions;
  const SidebarSpec(this.type, this.name, this.icon, this.height, {this.locked = false, this.hasOptions = false});
}

const List<SidebarSpec> sidebarCatalog = [
  SidebarSpec('logo', '로고 · 매장 이름', Icons.storefront, 126, locked: true, hasOptions: true),
  SidebarSpec('room', '방 번호', Icons.meeting_room_outlined, 88),
  SidebarSpec('staffCall', '직원 호출', Icons.notifications_active_outlined, 64),
  SidebarSpec('phone', '매장 전화번호', Icons.call_outlined, 22),
  SidebarSpec('clock', '시계', Icons.schedule, 80),
  SidebarSpec('links', '메뉴 바로가기', Icons.menu, 0, hasOptions: true), // 높이는 고른 메뉴 수로 계산
  SidebarSpec('note', '짧은 문구', Icons.short_text, 76, hasOptions: true),
  SidebarSpec('wifi', '와이파이 정보', Icons.wifi, 84, hasOptions: true),
  SidebarSpec('qr', '리뷰 QR', Icons.qr_code_2, 170, hasOptions: true),
  SidebarSpec('spacer', '빈 공간', Icons.unfold_more, 0),
];

SidebarSpec? sidebarSpecOf(String type) {
  for (final s in sidebarCatalog) {
    if (s.type == type) return s;
  }
  return null;
}

/// 관리자 화면 크기 목록에 보여줄 크기들 (위젯마다 허용되지 않는 크기는 고르면 경고)
const List<WidgetSize> allGridSizes = [
  WidgetSize(1, 1),
  WidgetSize(2, 1),
  WidgetSize(3, 1),
  WidgetSize(4, 1),
  WidgetSize(1, 2),
  WidgetSize(2, 2),
  WidgetSize(3, 2),
  WidgetSize(4, 2),
  WidgetSize(2, 3),
  WidgetSize(2, 4),
  WidgetSize(3, 4),
  WidgetSize(2, 5),
  WidgetSize(3, 5),
  WidgetSize(2, 6),
  WidgetSize(3, 6),
];

/// 메뉴 바로가기(links)에서 고를 수 있는 화면
const Map<String, String> linkTargets = {
  'games': '게임 목록',
  'food': '음식 주문',
  'recommended': '추천 게임',
  'event': '이벤트',
  'notice': '이용안내',
  'tools': '게임도구',
};

/// 왼쪽 영역 배경색 후보
const List<Color> sidebarColors = [
  Color(0xFF2A2420), // 짙은 갈색
  Color(0xFF1F3A2A), // 짙은 초록
  Color(0xFF23314D), // 짙은 남색
  Color(0xFFEFE6D6), // 밝은 크림
];

String colorToHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color colorFromHex(String? hex, Color fallback) {
  if (hex == null) return fallback;
  final s = hex.replaceAll('#', '');
  final v = int.tryParse(s, radix: 16);
  if (v == null || s.length != 6) return fallback;
  return Color(0xFF000000 | v);
}

Map<String, dynamic> _optionsFrom(dynamic raw) {
  if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
  return {};
}

int _int(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

class SidebarItem {
  final String type;
  final Map<String, dynamic> options;
  const SidebarItem(this.type, [this.options = const {}]);

  Map<String, dynamic> toMap() => {'type': type, if (options.isNotEmpty) 'options': options};

  static SidebarItem? fromAny(dynamic raw) {
    // "logo" 처럼 문자열만 있어도 되고, {type, options} 형태도 됨
    if (raw is String) return sidebarSpecOf(raw) == null ? null : SidebarItem(raw);
    if (raw is Map) {
      final type = raw['type']?.toString() ?? '';
      if (sidebarSpecOf(type) == null) return null;
      return SidebarItem(type, _optionsFrom(raw['options']));
    }
    return null;
  }

  SidebarItem copyWith({Map<String, dynamic>? options}) => SidebarItem(type, options ?? this.options);

  /// 넘침 검사용 높이
  double get estimatedHeight {
    if (type == 'links') {
      final targets = (options['targets'] is List) ? (options['targets'] as List).length : 3;
      return (targets + 1) * 60.0; // 맨 위 '홈' 줄 포함
    }
    return sidebarSpecOf(type)?.height ?? 0;
  }
}

class GridItem {
  final String id;
  final String type;
  final int x;
  final int y;
  final int w;
  final int h;
  final Map<String, dynamic> options;

  const GridItem({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.options = const {},
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        if (options.isNotEmpty) 'options': options,
      };

  static GridItem? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final type = raw['type']?.toString() ?? '';
    final spec = specOf(type);
    if (spec == null) return null;
    final def = spec.sizes.first;
    return GridItem(
      id: raw['id']?.toString() ?? 'w${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      x: _int(raw['x'], 0),
      y: _int(raw['y'], 0),
      w: _int(raw['w'], def.w),
      h: _int(raw['h'], def.h),
      options: _optionsFrom(raw['options']),
    );
  }

  GridItem copyWith({int? x, int? y, int? w, int? h, Map<String, dynamic>? options}) => GridItem(
        id: id,
        type: type,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        options: options ?? this.options,
      );

  bool overlaps(GridItem o) => x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h;
}

class HomeLayout {
  /// 세로 줄 수. 반 칸 단위라 8줄 (예전 4줄 배치는 읽을 때 y·h를 2배로 바꿈)
  static const int rows = 8;
  static const double designWidth = 1280;
  static const double designHeight = 800;
  static const double sidebarWidth = 196;
  static const double sidebarMaxContent = 740; // 왼쪽 영역 안쪽 높이 (위아래 여백 제외)

  /// 손님 화면 크기에 맞춘 그리기 크기. 1280×800(16:10)을 기준으로
  /// 화면이 더 넓으면 가로를, 더 길쭉하면 세로를 늘려서 빈 띠 없이 꽉 차게 그림.
  static Size designSizeFor(Size screen) {
    if (screen.width <= 0 || screen.height <= 0) return const Size(designWidth, designHeight);
    final aspect = screen.width / screen.height;
    const base = designWidth / designHeight;
    if (aspect >= base) return Size(designHeight * aspect, designHeight);
    return Size(designWidth, designWidth / aspect);
  }

  final bool sidebarVisible;
  final Color sidebarColor;
  final List<SidebarItem> sidebarItems;
  final List<GridItem> widgets;

  /// 보관함: 관리자가 잠깐 빼 둔 위젯 (설정은 그대로 남음). 손님 화면에는 안 그려지고 검사에서도 빠짐
  final List<GridItem> parked;

  const HomeLayout({
    required this.sidebarVisible,
    required this.sidebarColor,
    required this.sidebarItems,
    required this.widgets,
    this.parked = const [],
  });

  int get cols => sidebarVisible ? 6 : 7;

  /// 왼쪽 영역 글자색 (배경이 밝으면 어두운 글씨)
  bool get sidebarIsLight => sidebarColor.computeLuminance() > 0.5;

  HomeLayout copyWith({
    bool? sidebarVisible,
    Color? sidebarColor,
    List<SidebarItem>? sidebarItems,
    List<GridItem>? widgets,
    List<GridItem>? parked,
  }) =>
      HomeLayout(
        sidebarVisible: sidebarVisible ?? this.sidebarVisible,
        sidebarColor: sidebarColor ?? this.sidebarColor,
        sidebarItems: sidebarItems ?? this.sidebarItems,
        widgets: widgets ?? this.widgets,
        parked: parked ?? this.parked,
      );

  Map<String, dynamic> toMap() => {
        'version': 1,
        'sidebar': {
          'visible': sidebarVisible,
          'color': colorToHex(sidebarColor),
          'items': sidebarItems.map((e) => e.toMap()).toList(),
        },
        'grid': {'cols': cols, 'rows': rows},
        'widgets': widgets.map((e) => e.toMap()).toList(),
        if (parked.isNotEmpty) 'parked': parked.map((e) => e.toMap()).toList(),
      };

  /// Firestore 문서에서 읽기. 알 수 없는 위젯은 버리고, 문제가 있으면 null (→ 기본 배치 사용)
  static HomeLayout? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    try {
      final sidebar = _optionsFrom(data['sidebar']);
      final items = <SidebarItem>[];
      if (sidebar['items'] is List) {
        for (final raw in sidebar['items'] as List) {
          final item = SidebarItem.fromAny(raw);
          if (item != null) items.add(item);
        }
      }
      var widgets = <GridItem>[];
      if (data['widgets'] is List) {
        for (final raw in data['widgets'] as List) {
          final item = GridItem.fromMap(raw);
          if (item != null) widgets.add(item);
        }
      }
      // 예전에 4줄 격자로 저장한 배치면 세로 위치·크기를 2배로 (8줄 = 반 칸 단위)
      final savedRows = _int(_optionsFrom(data['grid'])['rows'], 4);
      if (savedRows == 4) {
        widgets = [for (final w in widgets) w.copyWith(y: w.y * 2, h: w.h * 2)];
      }
      // 보관함 (모르는 위젯·격자와 id가 겹치는 것은 버림)
      final parked = <GridItem>[];
      if (data['parked'] is List) {
        for (final raw in data['parked'] as List) {
          final item = GridItem.fromMap(raw);
          if (item == null) continue;
          if (widgets.any((w) => w.id == item.id) || parked.any((p) => p.id == item.id)) continue;
          parked.add(item);
        }
      }
      final layout = HomeLayout(
        sidebarVisible: sidebar['visible'] != false,
        sidebarColor: colorFromHex(sidebar['color']?.toString(), sidebarColors.first),
        sidebarItems: items,
        widgets: widgets,
        parked: parked,
      );
      // 저장된 배치가 규칙에 안 맞으면(손으로 고친 문서 등) 쓰지 않음
      return layout.validate().isEmpty ? layout : null;
    } catch (_) {
      return null;
    }
  }

  /// 저장 전 검사. 문제가 없으면 빈 목록
  List<String> validate() {
    final errors = <String>[];
    for (final w in widgets) {
      final spec = specOf(w.type);
      final name = spec?.name ?? w.type;
      if (spec == null) {
        errors.add('알 수 없는 위젯이 있어요: ${w.type}');
        continue;
      }
      if (!spec.sizes.contains(WidgetSize(w.w, w.h))) {
        errors.add('$name: ${w.w}×${w.h} 크기는 쓸 수 없어요.');
      }
      if (w.x < 0 || w.y < 0 || w.x + w.w > cols || w.y + w.h > rows) {
        errors.add('$name: 화면 밖으로 나갔어요. 위치나 크기를 바꿔 주세요.');
      }
    }
    for (var i = 0; i < widgets.length; i++) {
      for (var j = i + 1; j < widgets.length; j++) {
        if (widgets[i].overlaps(widgets[j])) {
          errors.add('${specOf(widgets[i].type)?.name} 와(과) ${specOf(widgets[j].type)?.name} 이(가) 겹쳐요.');
        }
      }
    }
    final callInSidebar = sidebarVisible && sidebarItems.any((e) => e.type == 'staffCall');
    final callInGrid = widgets.any((e) => e.type == 'staffCall');
    if (!callInSidebar && !callInGrid) {
      errors.add('직원 호출이 화면에 하나는 있어야 해요. 왼쪽 영역이나 격자에 넣어 주세요.');
    }
    if (sidebarVisible) {
      if (!sidebarItems.any((e) => e.type == 'logo')) {
        errors.add('왼쪽 영역에 로고가 있어야 해요. (빠르게 10번 눌러 로그아웃 기능)');
      }
      final used = sidebarItems.fold<double>(0, (sum, e) => sum + e.estimatedHeight) + (sidebarItems.length - 1) * 14;
      if (used > sidebarMaxContent) {
        errors.add('왼쪽 영역에 요소가 너무 많아 넘쳐요. 아래쪽 요소부터 줄여 주세요.');
      }
    }
    return errors;
  }

  // ── 화면 위 위치 계산 (1280×800 기준). 손님 화면과 관리자 끌어 놓기가 같이 씀 ──
  static const double gap = 16;
  static const double gridPadH = 28;
  static const double gridPadV = 26;

  double get gridLeft => (sidebarVisible ? sidebarWidth : 0) + gridPadH;
  double get gridTop => gridPadV;
  double get gridWidth => designWidth - (sidebarVisible ? sidebarWidth : 0) - gridPadH * 2;
  double get gridHeight => designHeight - gridPadV * 2;
  double get cellWidth => (gridWidth - gap * (cols - 1)) / cols;
  double get cellHeight => (gridHeight - gap * (rows - 1)) / rows;

  /// 칸 위치·크기 → 화면 위 사각형 (격자 안쪽 기준이면 inGrid: true)
  Rect cellRect(int x, int y, int w, int h, {bool inGrid = false}) {
    final left = (inGrid ? 0 : gridLeft) + x * (cellWidth + gap);
    final top = (inGrid ? 0 : gridTop) + y * (cellHeight + gap);
    return Rect.fromLTWH(left, top, w * cellWidth + (w - 1) * gap, h * cellHeight + (h - 1) * gap);
  }

  /// 위젯을 이 자리·크기로 바꿨을 때 문제 (없으면 null)
  String? problemFor(GridItem moved) {
    final spec = specOf(moved.type);
    if (spec != null && !spec.sizes.contains(WidgetSize(moved.w, moved.h))) {
      return '${spec.name}은(는) ${moved.w}×${moved.h} 크기를 쓸 수 없어요. (가능: ${spec.sizes.map((s) => s.label).join(', ')})';
    }
    if (moved.x < 0 || moved.y < 0 || moved.x + moved.w > cols || moved.y + moved.h > rows) {
      return '화면 밖으로 나가서 놓을 수 없어요.';
    }
    for (final o in widgets) {
      if (o.id != moved.id && o.overlaps(moved)) {
        return '${specOf(o.type)?.name ?? '다른 위젯'}과(와) 겹쳐서 놓을 수 없어요.';
      }
    }
    return null;
  }

  /// 위젯을 다른 위젯 위로 끌어 놓았을 때 자리 바꾸기 결과. 바꿀 수 없으면 null
  ///
  /// 1) 놓은 자리에 걸린 위젯들을 옮긴 위젯이 움직인 만큼 반대로 옮겨서(= 원래 자리로) 보내 봄.
  ///    크기가 같은 위젯끼리 1:1, 또는 2×2 하나 ↔ 2×1 두 개처럼 묶음으로도 바뀜.
  /// 2) 안 되면, 가장 많이 겹친 위젯이 같은 크기일 때 그 위젯 자리로 딱 맞춰서 맞바꿔 봄
  ///    (반 칸 어긋나게 놓아도 바꿔지도록).
  /// 결과의 moved는 실제로 놓일 자리, displaced는 밀려나는 위젯들의 새 자리.
  ({List<GridItem> widgets, GridItem moved, List<GridItem> displaced})? swapFor(GridItem moved) {
    GridItem? original;
    for (final w in widgets) {
      if (w.id == moved.id) original = w;
    }
    if (original == null || original.w != moved.w || original.h != moved.h) return null;
    final first = _trySwap(original, moved);
    if (first != null) return first;

    GridItem? best;
    var bestArea = 0;
    for (final o in widgets) {
      if (o.id == moved.id || !o.overlaps(moved)) continue;
      final area = _overlapArea(o, moved);
      if (area > bestArea) {
        best = o;
        bestArea = area;
      }
    }
    if (best == null || best.w != moved.w || best.h != moved.h) return null;
    return _trySwap(original, moved.copyWith(x: best.x, y: best.y));
  }

  ({List<GridItem> widgets, GridItem moved, List<GridItem> displaced})? _trySwap(GridItem original, GridItem moved) {
    if (moved.x == original.x && moved.y == original.y) return null;
    final hit = [for (final o in widgets) if (o.id != moved.id && o.overlaps(moved)) o];
    if (hit.isEmpty) return null;
    final dx = original.x - moved.x;
    final dy = original.y - moved.y;
    final shifted = {for (final o in hit) o.id: o.copyWith(x: o.x + dx, y: o.y + dy)};
    final next = [
      for (final w in widgets)
        if (w.id == moved.id) moved else shifted[w.id] ?? w,
    ];
    for (final w in next) {
      if (w.x < 0 || w.y < 0 || w.x + w.w > cols || w.y + w.h > rows) return null;
    }
    for (var i = 0; i < next.length; i++) {
      for (var j = i + 1; j < next.length; j++) {
        if (next[i].overlaps(next[j])) return null;
      }
    }
    return (widgets: next, moved: moved, displaced: shifted.values.toList());
  }

  static int _overlapArea(GridItem a, GridItem b) {
    final w = (a.x + a.w < b.x + b.w ? a.x + a.w : b.x + b.w) - (a.x > b.x ? a.x : b.x);
    final h = (a.y + a.h < b.y + b.h ? a.y + a.h : b.y + b.h) - (a.y > b.y ? a.y : b.y);
    return w > 0 && h > 0 ? w * h : 0;
  }

  /// 보관함 위젯을 격자 (cx, cy) 칸 근처에 넣을 자리. 지금 크기부터, 안 되면 허용된 다른 크기로 시도.
  /// 들어갈 수 있으면 (item, null), 없으면 (지금 크기 후보, 이유)
  (GridItem, String?) placeParked(GridItem item, int cx, int cy) {
    final spec = specOf(item.type);
    final sizes = <WidgetSize>[WidgetSize(item.w, item.h), ...?spec?.sizes];
    GridItem? firstTry;
    String? firstProblem;
    for (final s in sizes) {
      if (s.w > cols || s.h > rows) continue;
      final x = (cx - (s.w - 1) ~/ 2).clamp(0, cols - s.w).toInt();
      final y = (cy - (s.h - 1) ~/ 2).clamp(0, rows - s.h).toInt();
      final candidate = item.copyWith(x: x, y: y, w: s.w, h: s.h);
      final problem = problemFor(candidate);
      if (problem == null) return (candidate, null);
      firstTry ??= candidate;
      firstProblem ??= problem;
    }
    return (firstTry ?? item, firstProblem ?? '여기에는 놓을 수 없어요.');
  }

  /// 위젯이 들어갈 빈자리 찾기 (위→아래, 왼→오른). 없으면 null
  ({int x, int y})? findSpot(int w, int h, {String? ignoreId}) {
    for (var y = 0; y + h <= rows; y++) {
      for (var x = 0; x + w <= cols; x++) {
        final probe = GridItem(id: '_probe', type: 'clock', x: x, y: y, w: w, h: h);
        final hit = widgets.any((o) => o.id != ignoreId && o.overlaps(probe));
        if (!hit) return (x: x, y: y);
      }
    }
    return null;
  }

  /// 내부 화면(게임 목록·음식 주문 등) 왼쪽 사이드바용 배치.
  /// 홈과 같은 왼쪽 영역을 쓰되, 왼쪽 영역을 꺼 뒀으면 기본 왼쪽 영역을 쓰고,
  /// 메뉴 바로가기가 없으면 로고 아래에 넣어 줌 (화면 이동이 되도록, 넘치지 않는 만큼만)
  HomeLayout forPadScreens() {
    var items = sidebarVisible ? sidebarItems : HomeLayout.defaults().sidebarItems;
    if (!items.any((e) => e.type == 'links')) {
      final used = items.fold<double>(0, (sum, e) => sum + e.estimatedHeight) + items.length * 14;
      final fit = ((sidebarMaxContent - used) / 60).floor() - 1; // '홈' 줄 한 칸 빼고
      const all = ['games', 'food', 'tools', 'event', 'notice'];
      final targets = all.take(fit.clamp(0, all.length).toInt()).toList();
      final at = items.indexWhere((e) => e.type == 'logo') + 1;
      items = [...items]..insert(at, SidebarItem('links', {'targets': targets}));
    }
    return HomeLayout(sidebarVisible: true, sidebarColor: sidebarColor, sidebarItems: items, widgets: widgets);
  }

  /// 처음 설치했을 때 / 저장된 배치를 못 읽었을 때 / '기본 배치로 되돌리기'에 쓰는 기본 배치 (L 시안)
  static HomeLayout defaults() => homeLayoutPresets.first.layout;
}

/// '예시 배치 고르기'에 나오는 배치들. 첫 번째가 기본 배치
class HomeLayoutPreset {
  final String name;
  final String description;
  final HomeLayout layout;
  const HomeLayoutPreset(this.name, this.description, this.layout);
}

const _kBrown = Color(0xFF2A2420);
const _kNavy = Color(0xFF23314D);
const _kCream = Color(0xFFEFE6D6);

// 격자는 왼쪽 영역이 있으면 가로 6칸 × 세로 8줄(반 칸 단위), 없으면 7칸 × 8줄
const List<HomeLayoutPreset> homeLayoutPresets = [
  HomeLayoutPreset(
    '기본 — 사진 카드',
    '인사말·검색 한 줄, 큰 사진 카드 두 개, 아래 추천·인원별·장르별·난이도별 버튼, 오른쪽 시계·방 번호·공지·이벤트',
    HomeLayout(
      sidebarVisible: true,
      sidebarColor: _kBrown,
      sidebarItems: [
        SidebarItem('logo'),
        SidebarItem('links', {
          'targets': ['event', 'tools', 'notice'],
        }),
        SidebarItem('spacer'),
        SidebarItem('staffCall'),
        SidebarItem('phone'),
      ],
      widgets: [
        GridItem(id: 'w1', type: 'greeting', x: 0, y: 0, w: 4, h: 1, options: {
          'small': '안녕하세요!',
          'text': '오늘도 즐거운 게임 시간 보내세요',
        }),
        GridItem(id: 'w2', type: 'search', x: 4, y: 0, w: 2, h: 1),
        GridItem(id: 'w3', type: 'foodOrder', x: 0, y: 1, w: 2, h: 6),
        GridItem(id: 'w4', type: 'gameList', x: 2, y: 1, w: 2, h: 6),
        GridItem(id: 'w5', type: 'recommended', x: 0, y: 7, w: 1, h: 1),
        GridItem(id: 'w6', type: 'finder', x: 1, y: 7, w: 3, h: 1),
        GridItem(id: 'w7', type: 'clock', x: 4, y: 1, w: 2, h: 1),
        GridItem(id: 'w8', type: 'room', x: 4, y: 2, w: 2, h: 1),
        GridItem(id: 'w9', type: 'notice', x: 4, y: 3, w: 2, h: 3),
        GridItem(id: 'w10', type: 'event', x: 4, y: 6, w: 2, h: 2),
      ],
    ),
  ),
  HomeLayoutPreset(
    '게임 찾기 중심',
    '게임 목록을 가장 크게, 검색·찾아보기를 바로 옆에. 주문은 아래에 작게',
    HomeLayout(
      sidebarVisible: true,
      sidebarColor: _kNavy,
      sidebarItems: [
        SidebarItem('logo'),
        SidebarItem('room'),
        SidebarItem('links', {
          'targets': ['games', 'food', 'tools'],
        }),
        SidebarItem('spacer'),
        SidebarItem('staffCall'),
        SidebarItem('phone'),
      ],
      widgets: [
        GridItem(id: 'w1', type: 'gameList', x: 0, y: 0, w: 3, h: 4),
        GridItem(id: 'w2', type: 'search', x: 3, y: 0, w: 3, h: 2),
        GridItem(id: 'w3', type: 'finder', x: 3, y: 2, w: 3, h: 2),
        GridItem(id: 'w4', type: 'foodOrder', x: 0, y: 4, w: 2, h: 4),
        GridItem(id: 'w5', type: 'recommended', x: 2, y: 4, w: 1, h: 2),
        GridItem(id: 'w6', type: 'tools', x: 2, y: 6, w: 1, h: 2),
        GridItem(id: 'w7', type: 'notice', x: 3, y: 4, w: 2, h: 2),
        GridItem(id: 'w8', type: 'dice', x: 5, y: 4, w: 1, h: 2),
        GridItem(id: 'w9', type: 'event', x: 3, y: 6, w: 2, h: 2),
        GridItem(id: 'w10', type: 'info', x: 5, y: 6, w: 1, h: 2),
      ],
    ),
  ),
  HomeLayoutPreset(
    '큰 카드 두 개',
    '음식 주문·게임 목록을 크게 나란히. 아래 줄에 자주 쓰는 바로가기',
    HomeLayout(
      sidebarVisible: true,
      sidebarColor: _kCream,
      sidebarItems: [
        SidebarItem('logo'),
        SidebarItem('room'),
        SidebarItem('links', {
          'targets': ['event', 'notice'],
        }),
        SidebarItem('spacer'),
        SidebarItem('staffCall'),
        SidebarItem('phone'),
      ],
      widgets: [
        GridItem(id: 'w1', type: 'foodOrder', x: 0, y: 0, w: 3, h: 4),
        GridItem(id: 'w2', type: 'gameList', x: 3, y: 0, w: 3, h: 4),
        GridItem(id: 'w3', type: 'search', x: 0, y: 4, w: 3, h: 2),
        GridItem(id: 'w4', type: 'notice', x: 3, y: 4, w: 2, h: 2),
        GridItem(id: 'w5', type: 'clock', x: 5, y: 4, w: 1, h: 2),
        GridItem(id: 'w6', type: 'finder', x: 0, y: 6, w: 3, h: 2),
        GridItem(id: 'w7', type: 'recommended', x: 3, y: 6, w: 1, h: 2),
        GridItem(id: 'w8', type: 'tools', x: 4, y: 6, w: 1, h: 2),
        GridItem(id: 'w9', type: 'event', x: 5, y: 6, w: 1, h: 2),
      ],
    ),
  ),
  HomeLayoutPreset(
    '왼쪽 영역 없이 넓게',
    '화면 전체를 7칸 격자로. 직원 호출·방 번호는 오른쪽 위에 (왼쪽 위 구석을 빠르게 10번 누르면 로그아웃)',
    HomeLayout(
      sidebarVisible: false,
      sidebarColor: _kBrown,
      sidebarItems: [
        SidebarItem('logo'),
        SidebarItem('room'),
        SidebarItem('spacer'),
        SidebarItem('staffCall'),
        SidebarItem('phone'),
      ],
      widgets: [
        GridItem(id: 'w1', type: 'foodOrder', x: 0, y: 0, w: 3, h: 4),
        GridItem(id: 'w2', type: 'gameList', x: 3, y: 0, w: 3, h: 4),
        GridItem(id: 'w3', type: 'staffCall', x: 6, y: 0, w: 1, h: 2),
        GridItem(id: 'w4', type: 'room', x: 6, y: 2, w: 1, h: 2),
        GridItem(id: 'w5', type: 'search', x: 0, y: 4, w: 3, h: 2),
        GridItem(id: 'w6', type: 'notice', x: 3, y: 4, w: 2, h: 2),
        GridItem(id: 'w7', type: 'clock', x: 5, y: 4, w: 1, h: 2),
        GridItem(id: 'w8', type: 'info', x: 6, y: 4, w: 1, h: 2),
        GridItem(id: 'w9', type: 'finder', x: 0, y: 6, w: 3, h: 2),
        GridItem(id: 'w10', type: 'event', x: 3, y: 6, w: 2, h: 2),
        GridItem(id: 'w11', type: 'recommended', x: 5, y: 6, w: 1, h: 2),
        GridItem(id: 'w12', type: 'tools', x: 6, y: 6, w: 1, h: 2),
      ],
    ),
  ),
];
