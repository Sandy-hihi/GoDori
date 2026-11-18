import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/services/store_scope.dart';

/// 특정 시간 자동 품절 (112차)
///
/// 저장: stores/{매장}/settings/soldOutSchedule = {
///   rules: [{ id, name, enabled, from: 'HH:mm', to: 'HH:mm', days: [1~7](월=1 … 일=7, 비면 매일),
///             categories: [카테고리 이름], menuIds: [메뉴 ID] }],
///   updatedAt }
/// - 붙는 메뉴 = categories에 든 카테고리의 메뉴 + menuIds의 메뉴
/// - 시간: from ≤ 지금 < to. from > to면 밤을 넘김(22:00~11:00 — 다음 날 11:00까지, 요일은 시작한 날 기준),
///   from == to면 그 요일 하루 종일
/// - 서버·메뉴 문서는 안 건드림: 손님 패드가 지금 시각(패드 기기 시계)으로 계산해서 '품절'로 보여 줌
///   → 메뉴의 손으로 켠 품절(isSoldOut)과 따로. 둘 중 하나라도 품절이면 품절
/// - 쓰기는 관리자만(firestore.rules settings 쓰기 목록 'soldOutSchedule'), 읽기는 누구나
class SoldOutRule {
  final String id;
  final String name;
  final bool enabled;
  final int from; // 0시부터 몇 분째 (0~1439)
  final int to;
  final List<int> days; // 1~7, 비면 매일
  final List<String> categories;
  final List<String> menuIds;

  const SoldOutRule({
    required this.id,
    this.name = '',
    this.enabled = true,
    this.from = 22 * 60,
    this.to = 11 * 60,
    this.days = const [],
    this.categories = const [],
    this.menuIds = const [],
  });

  static int? parseTime(dynamic v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((v ?? '').toString().trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return h * 60 + mi;
  }

  static String formatTime(int minutes) {
    final m = ((minutes % 1440) + 1440) % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  static SoldOutRule? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    if (id.isEmpty) return null;
    List<String> strs(dynamic v) => v is List ? v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() : <String>[];
    final days = raw['days'] is List
        ? (raw['days'] as List)
            .map((e) => e is num ? e.toInt() : int.tryParse('$e'))
            .whereType<int>()
            .where((d) => d >= 1 && d <= 7)
            .toSet()
            .toList()
        : <int>[];
    days.sort();
    return SoldOutRule(
      id: id,
      name: (raw['name'] ?? '').toString(),
      enabled: raw['enabled'] != false,
      from: parseTime(raw['from']) ?? 22 * 60,
      to: parseTime(raw['to']) ?? 11 * 60,
      days: days.length == 7 ? const [] : days,
      categories: strs(raw['categories']),
      menuIds: strs(raw['menuIds']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'from': formatTime(from),
        'to': formatTime(to),
        'days': days,
        'categories': categories,
        'menuIds': menuIds,
      };

  SoldOutRule copyWith({
    String? name,
    bool? enabled,
    int? from,
    int? to,
    List<int>? days,
    List<String>? categories,
    List<String>? menuIds,
  }) =>
      SoldOutRule(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        from: from ?? this.from,
        to: to ?? this.to,
        days: days ?? this.days,
        categories: categories ?? this.categories,
        menuIds: menuIds ?? this.menuIds,
      );

  bool appliesTo(String menuId, String category) =>
      (menuId.isNotEmpty && menuIds.contains(menuId)) || (category.isNotEmpty && categories.contains(category));

  bool _dayOk(int weekday) => days.isEmpty || days.contains(weekday);

  /// 지금 이 규칙 시간 안인지 (꺼진 규칙은 false)
  bool activeAt(DateTime now) {
    if (!enabled) return false;
    final m = now.hour * 60 + now.minute;
    if (from == to) return _dayOk(now.weekday); // 하루 종일
    if (from < to) return _dayOk(now.weekday) && m >= from && m < to;
    // 밤을 넘김: 시작한 날 from~24:00 + 다음 날 0:00~to
    if (m >= from) return _dayOk(now.weekday);
    if (m < to) return _dayOk(now.weekday == 1 ? 7 : now.weekday - 1);
    return false;
  }

  static const _dayNames = ['월', '화', '수', '목', '금', '토', '일'];

  /// '매일' / '월·화·수' / '평일' / '주말'
  String get daysLabel {
    if (days.isEmpty) return '매일';
    if (days.length == 5 && days.every((d) => d <= 5)) return '평일';
    if (days.length == 2 && days.contains(6) && days.contains(7)) return '주말';
    return days.map((d) => _dayNames[d - 1]).join('·');
  }

  /// '22:00 ~ 다음 날 11:00' / '하루 종일'
  String get timeLabel {
    if (from == to) return '하루 종일';
    return '${formatTime(from)} ~ ${from > to ? '다음 날 ' : ''}${formatTime(to)}';
  }

  /// 지금 시간 안이면 언제 풀리는지 ('11:00까지')
  String get untilLabel => from == to ? '오늘 하루' : '${formatTime(to)}까지';
}

class SoldOutSchedule {
  static DocumentReference<Map<String, dynamic>> get _doc => StoreScope.col('settings').doc('soldOutSchedule');

  static List<SoldOutRule> parse(Map<String, dynamic>? data) {
    final raw = data?['rules'];
    if (raw is! List) return const [];
    return raw.map(SoldOutRule.fromJson).whereType<SoldOutRule>().toList();
  }

  static Future<List<SoldOutRule>> load() async {
    try {
      return parse((await _doc.get()).data());
    } catch (_) {
      return const [];
    }
  }

  /// 규칙이 바뀔 때 + 30초마다(시각이 넘어가면 품절이 켜지고 풀리게) 다시 알려 줌.
  /// 규칙이 하나도 없으면 30초 알림은 안 보냄
  static Stream<List<SoldOutRule>> watchTicking({Duration tick = const Duration(seconds: 30)}) {
    late StreamController<List<SoldOutRule>> ctrl;
    StreamSubscription? sub;
    Timer? timer;
    var last = const <SoldOutRule>[];
    ctrl = StreamController<List<SoldOutRule>>(
      onListen: () {
        sub = _doc.snapshots().listen((s) {
          last = parse(s.data());
          ctrl.add(last);
        }, onError: (_) {}); // 규칙 배포 전·권한 없음이면 자동 품절 없이
        timer = Timer.periodic(tick, (_) {
          if (last.isNotEmpty) ctrl.add(last);
        });
      },
      onCancel: () async {
        timer?.cancel();
        await sub?.cancel();
      },
    );
    return ctrl.stream;
  }

  static Future<void> save(List<SoldOutRule> rules) =>
      _doc.set({'rules': rules.map((r) => r.toJson()).toList(), 'updatedAt': FieldValue.serverTimestamp()});

  /// 메뉴에 지금 걸린 규칙 (없으면 null)
  static SoldOutRule? activeFor(List<SoldOutRule> rules, String menuId, String category, DateTime now) {
    for (final r in rules) {
      if (r.appliesTo(menuId, category) && r.activeAt(now)) return r;
    }
    return null;
  }

  /// 메뉴에 붙은 규칙 전부 (꺼진 것 포함)
  static List<SoldOutRule> rulesFor(List<SoldOutRule> rules, String menuId, String category) =>
      [for (final r in rules) if (r.appliesTo(menuId, category)) r];

  /// 메뉴 문서가 지금 품절인지 — 손으로 켠 품절(isSoldOut) 또는 포스 품절(posSoldOut — 113차, 서버가 토스 포스 상품 품절을 따라 씀) 또는 자동 품절
  static bool menuSoldOut(Map<String, dynamic> menu, String menuId, List<SoldOutRule> rules, [DateTime? now]) {
    if (menu['isSoldOut'] == true || menu['isSoldOut'] == 'true') return true;
    if (menu['posSoldOut'] == true) return true;
    if (rules.isEmpty) return false;
    return activeFor(rules, menuId, (menu['category'] ?? '').toString(), now ?? DateTime.now()) != null;
  }

  /// 카테고리 이름을 바꾸면 규칙의 붙는 카테고리도 (메뉴 관리 카테고리 수정)
  static Future<void> renameCategory(String oldName, String newName) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_doc);
      final rules = parse(snap.data());
      if (!rules.any((r) => r.categories.contains(oldName))) return;
      final next = [
        for (final r in rules)
          r.categories.contains(oldName)
              ? r.copyWith(categories: {for (final c in r.categories) c == oldName ? newName : c}.toList())
              : r,
      ];
      tx.set(_doc, {'rules': next.map((r) => r.toJson()).toList(), 'updatedAt': FieldValue.serverTimestamp()});
    });
  }
}
