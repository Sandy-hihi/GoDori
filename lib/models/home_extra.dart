/// 134차: 새 홈 위젯들의 계산 (Firebase·화면 없이 — 테스트에서 바로 씀)
///   - 랜덤 게임 뽑기: gameFitsPlayers
///   - 새로 들어온 게임: newGamesOf
///   - 매장 전화번호·영업시간: StoreHours
///   - 내 음식 상태: foodOrderStep
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:boardpad/models/order_flow.dart';
import 'package:boardpad/utils/game_meta.dart';

/// n명이 할 수 있는 게임인지. minPlayers·maxPlayers → 없으면 'players' 글('2~4인'·'2인').
/// orMore('6+'): 최대 인원이 n명 이상이면. 인원을 모르는 게임은 false.
bool gameFitsPlayers(Map<String, dynamic> game, int n, {bool orMore = false}) {
  int? lo = asInt(game['minPlayers']);
  int? hi = asInt(game['maxPlayers']);
  if (lo == null && hi == null) {
    final nums = RegExp(r'\d+')
        .allMatches((game['players'] ?? '').toString())
        .map((m) => int.parse(m[0]!))
        .toList();
    if (nums.isEmpty) return false;
    lo = nums.first;
    hi = nums.last;
  }
  final min = lo ?? hi!;
  final max = hi ?? lo!;
  if (orMore) return max >= n;
  return min <= n && n <= max;
}

/// 랜덤 게임 뽑기 후보 — 확장판은 뺌. players가 null이면 인원 상관없이
List<Map<String, dynamic>> randomGameCandidates(List<Map<String, dynamic>> games, int? players) {
  return games.where((g) {
    if (g['expansion'] == true) return false;
    if (players == null) return true;
    return gameFitsPlayers(g, players, orMore: players >= 6);
  }).toList();
}

/// 새로 들어온 게임 (NEW 배지와 같은 기준 — 등록 30일 이내·매장에서 안 끈 것), 최근 것부터
List<Map<String, dynamic>> newGamesOf(List<Map<String, dynamic>> games, {int limit = 24}) {
  int ms(Map<String, dynamic> g) {
    final t = g['timestamp'];
    return t is Timestamp ? t.millisecondsSinceEpoch : 0;
  }

  final list = games.where(isNewGame).toList()..sort((a, b) => ms(b).compareTo(ms(a)));
  return list.take(limit).toList();
}

/// 영업시간 (홈 위젯 options: open·close·lastOrder 'HH:MM', closedDays [1=월 … 7=일])
/// close가 open보다 이르거나 같으면 다음 날 새벽까지(같으면 24시간).
class StoreHours {
  final int? open; // 분 (0~1440)
  final int? close;
  final int? lastOrder;
  final List<int> closedDays;

  const StoreHours({this.open, this.close, this.lastOrder, this.closedDays = const []});

  static const dayNames = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  static const dayShort = ['월', '화', '수', '목', '금', '토', '일'];

  /// '9:00'·'24:00' → 분. 잘못된 글이면 null
  static int? parseTime(Object? v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((v ?? '').toString().trim());
    if (m == null) return null;
    final h = int.parse(m[1]!), mi = int.parse(m[2]!);
    if (h > 24 || mi > 59 || (h == 24 && mi > 0)) return null;
    return h * 60 + mi;
  }

  static String timeText(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  factory StoreHours.fromOptions(Map<String, dynamic> o) {
    final days = o['closedDays'];
    return StoreHours(
      open: parseTime(o['open']),
      close: parseTime(o['close']),
      lastOrder: parseTime(o['lastOrder']),
      closedDays: days is List
          ? (days.map((e) => e is num ? e.toInt() : int.tryParse('$e') ?? 0).where((d) => d >= 1 && d <= 7).toSet().toList()
            ..sort())
          : const [],
    );
  }

  bool get hasHours => open != null && close != null;

  /// '12:00 – 02:00'
  String get rangeText => hasHours ? '${timeText(open!)} – ${timeText(close!)}' : '';

  /// 지금 영업 중인지 (영업시간이 없으면 null)
  bool? isOpenAt(DateTime t) {
    if (!hasHours) return null;
    final o = open!, c = close!;
    final m = t.hour * 60 + t.minute;
    final today = t.weekday;
    final yesterday = today == 1 ? 7 : today - 1;
    if (o == c) return !closedDays.contains(today); // 24시간
    if (c > o) return !closedDays.contains(today) && m >= o && m < c;
    // 자정 넘김: 오늘 문 연 뒤 또는 어제 영업의 새벽
    if (m >= o) return !closedDays.contains(today);
    if (m < c) return !closedDays.contains(yesterday);
    return false;
  }
}

/// 내 음식 상태 — 주문 상태를 단계로. 단계 이름(한국어, 화면에서 번역)과 지금 몇 번째인지(0부터)
({List<String> steps, int index}) foodOrderStep(String status, OrderFlow flow) {
  final steps = flow.isPickup ? const ['주문 접수', '준비 중', '준비 완료'] : const ['주문 접수', '준비 중', '자리로 전달'];
  final index = switch (status) { 'pending' => 0, 'preparing' => 1, 'ready' => 2, _ => 2 };
  return (steps: steps, index: index);
}
