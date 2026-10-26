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

  String get label => '$w×$h';

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

const List<WidgetSpec> widgetCatalog = [
  // 게임
  WidgetSpec('gameList', '게임 목록', '사진 카드 — 누르면 게임 목록', Icons.casino_outlined, WidgetCategory.game,
      [WidgetSize(2, 2), WidgetSize(3, 2), WidgetSize(2, 3)]),
  WidgetSpec('aiPick', '오늘의 추천 게임 (AI)', '매일 AI가 고른 게임 + 맞춤 추천', Icons.auto_awesome, WidgetCategory.game,
      [WidgetSize(2, 2), WidgetSize(3, 2), WidgetSize(2, 3)],
      hasOptions: true),
  WidgetSpec('search', '게임 검색', '게임 이름 검색창', Icons.search, WidgetCategory.game, [WidgetSize(2, 1), WidgetSize(3, 1)]),
  WidgetSpec('finder', '찾아보기', '인원별·장르별·난이도별 찾기', Icons.tune, WidgetCategory.game,
      [WidgetSize(2, 1), WidgetSize(3, 1)]),
  WidgetSpec('recommended', '추천 게임', '직원 추천 게임만 모아 보기', Icons.star_rounded, WidgetCategory.game, [WidgetSize(1, 1)]),
  // 주문
  WidgetSpec('foodOrder', '음식 주문', '사진 카드 — 누르면 주문 화면', Icons.restaurant, WidgetCategory.order,
      [WidgetSize(2, 2), WidgetSize(3, 2), WidgetSize(2, 3)]),
  WidgetSpec('menuPick', '오늘의 추천 메뉴', '고른 메뉴로 바로 주문', Icons.local_cafe_outlined, WidgetCategory.order,
      [WidgetSize(2, 1)],
      hasOptions: true),
  // 테이블
  WidgetSpec('clock', '시계', '현재 시각과 날짜', Icons.schedule, WidgetCategory.table, [WidgetSize(1, 1)]),
  WidgetSpec('room', '방 번호', '지금 이용 중인 방', Icons.meeting_room_outlined, WidgetCategory.table, [WidgetSize(1, 1)]),
  WidgetSpec('staffCall', '직원 호출', '직원 호출 버튼', Icons.notifications_active_outlined, WidgetCategory.table,
      [WidgetSize(1, 1), WidgetSize(2, 1)]),
  // 매장 정보
  WidgetSpec('notice', '공지사항', '가장 최근 공지 제목', Icons.campaign_outlined, WidgetCategory.info, [WidgetSize(2, 1)]),
  WidgetSpec('event', '이벤트', '진행 중인 이벤트', Icons.card_giftcard_outlined, WidgetCategory.info,
      [WidgetSize(2, 1), WidgetSize(1, 1)]),
  WidgetSpec('fee', '요금 안내', '요금표 (직접 입력)', Icons.payments_outlined, WidgetCategory.info, [WidgetSize(2, 1)],
      hasOptions: true),
  WidgetSpec('info', '이용안내', '이용안내 화면 바로가기', Icons.article_outlined, WidgetCategory.info, [WidgetSize(1, 1)]),
  WidgetSpec('wifi', '와이파이', '와이파이 이름·비밀번호', Icons.wifi, WidgetCategory.info, [WidgetSize(1, 1)],
      hasOptions: true),
  WidgetSpec('qr', '인스타·리뷰 QR', '링크를 QR로 보여주기', Icons.qr_code_2, WidgetCategory.info, [WidgetSize(1, 1)],
      hasOptions: true),
  // 게임 도구
  WidgetSpec('tools', '게임도구', '게임도구 화면 바로가기', Icons.timer_outlined, WidgetCategory.tools, [WidgetSize(1, 1)]),
  WidgetSpec('timer', '타이머', '홈에서 바로 쓰는 타이머', Icons.hourglass_bottom, WidgetCategory.tools, [WidgetSize(1, 1)],
      hasOptions: true),
  WidgetSpec('dice', '주사위', '눌러서 굴리기', Icons.casino, WidgetCategory.tools, [WidgetSize(1, 1)]),
  // 꾸미기
  WidgetSpec('banner', '사진 배너', '사진 + 문구, 누르면 원하는 화면으로', Icons.image_outlined, WidgetCategory.decor,
      [WidgetSize(2, 1), WidgetSize(4, 1)],
      hasOptions: true),
  WidgetSpec('memo', '자유 문구', '사장님이 쓰는 안내 문구', Icons.sticky_note_2_outlined, WidgetCategory.decor,
      [WidgetSize(2, 1)],
      hasOptions: true),
];

WidgetSpec? specOf(String type) {
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
  SidebarSpec('logo', '로고 · 매장 이름', Icons.storefront, 126, locked: true),
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
      return targets * 60.0;
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
  static const int rows = 4;
  static const double designWidth = 1280;
  static const double designHeight = 800;
  static const double sidebarWidth = 196;
  static const double sidebarMaxContent = 740; // 왼쪽 영역 안쪽 높이 (위아래 여백 제외)

  final bool sidebarVisible;
  final Color sidebarColor;
  final List<SidebarItem> sidebarItems;
  final List<GridItem> widgets;

  const HomeLayout({
    required this.sidebarVisible,
    required this.sidebarColor,
    required this.sidebarItems,
    required this.widgets,
  });

  int get cols => sidebarVisible ? 6 : 7;

  /// 왼쪽 영역 글자색 (배경이 밝으면 어두운 글씨)
  bool get sidebarIsLight => sidebarColor.computeLuminance() > 0.5;

  HomeLayout copyWith({
    bool? sidebarVisible,
    Color? sidebarColor,
    List<SidebarItem>? sidebarItems,
    List<GridItem>? widgets,
  }) =>
      HomeLayout(
        sidebarVisible: sidebarVisible ?? this.sidebarVisible,
        sidebarColor: sidebarColor ?? this.sidebarColor,
        sidebarItems: sidebarItems ?? this.sidebarItems,
        widgets: widgets ?? this.widgets,
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
      final widgets = <GridItem>[];
      if (data['widgets'] is List) {
        for (final raw in data['widgets'] as List) {
          final item = GridItem.fromMap(raw);
          if (item != null) widgets.add(item);
        }
      }
      final layout = HomeLayout(
        sidebarVisible: sidebar['visible'] != false,
        sidebarColor: colorFromHex(sidebar['color']?.toString(), sidebarColors.first),
        sidebarItems: items,
        widgets: widgets,
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
        errors.add('왼쪽 영역에 로고가 있어야 해요. (5초 눌러 패드 종료 기능)');
      }
      final used = sidebarItems.fold<double>(0, (sum, e) => sum + e.estimatedHeight) + (sidebarItems.length - 1) * 14;
      if (used > sidebarMaxContent) {
        errors.add('왼쪽 영역에 요소가 너무 많아 넘쳐요. 아래쪽 요소부터 줄여 주세요.');
      }
    }
    return errors;
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

  /// 처음 설치했을 때 / 저장된 배치를 못 읽었을 때 쓰는 기본 배치
  static HomeLayout defaults() => const HomeLayout(
        sidebarVisible: true,
        sidebarColor: Color(0xFF2A2420),
        sidebarItems: [
          SidebarItem('logo'),
          SidebarItem('room'),
          SidebarItem('spacer'),
          SidebarItem('staffCall'),
          SidebarItem('phone'),
        ],
        widgets: [
          GridItem(id: 'w1', type: 'gameList', x: 0, y: 0, w: 2, h: 2),
          GridItem(id: 'w2', type: 'foodOrder', x: 2, y: 0, w: 2, h: 2),
          GridItem(id: 'w3', type: 'aiPick', x: 4, y: 0, w: 2, h: 2),
          GridItem(id: 'w4', type: 'search', x: 0, y: 2, w: 2, h: 1),
          GridItem(id: 'w5', type: 'notice', x: 2, y: 2, w: 2, h: 1),
          GridItem(id: 'w6', type: 'clock', x: 4, y: 2, w: 1, h: 1),
          GridItem(id: 'w7', type: 'info', x: 5, y: 2, w: 1, h: 1),
          GridItem(id: 'w8', type: 'finder', x: 0, y: 3, w: 2, h: 1),
          GridItem(id: 'w9', type: 'event', x: 2, y: 3, w: 2, h: 1),
          GridItem(id: 'w10', type: 'tools', x: 4, y: 3, w: 1, h: 1),
          GridItem(id: 'w11', type: 'recommended', x: 5, y: 3, w: 1, h: 1),
        ],
      );
}
