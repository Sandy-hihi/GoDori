/// 관리자 '방 현황판' (112차) — 방마다 이용 중·주문·결제 대기를 한눈에
///
/// 읽는 것 (모두 관리자만 읽기 가능 — firestore.rules):
///  - roomStatus/{방}  (81·84차, 서버만 씀 — 토스 POS 연동 매장만 생김)
///      open: 포스로 보내고 아직 결제·취소 안 된 주문 ID → 비어 있지 않으면 '결제 대기'
///      cycle: 이번 손님 주문 요약 (state open·paid·cancelled) — 결제가 다 끝나면(settledAt) 비워짐
///      settledAt: 마지막 정산 시각(ISO)
///  - orders 중 status pending·preparing·ready (아직 손님에게 안 간 주문)
///  - staff_calls 중 isAcknowledged == false (확인 안 한 직원 호출)
///  - settings/rooms.count (방 개수)
/// 상태: 결제 대기(open이 있음) > 이용 중(cycle·진행 중 주문·호출 중 하나라도) > 비어 있음
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:boardpad/models/order_history.dart';

enum RoomBoardState { empty, inUse, awaitingPay }

class RoomBoardOrder {
  final String id;
  final String status; // pending | preparing | ready
  final DateTime? at;
  final List<String> items;
  final int price;
  const RoomBoardOrder({required this.id, required this.status, this.at, this.items = const [], this.price = 0});

  String get statusLabel => switch (status) {
        'pending' => '접수',
        'preparing' => '준비 중',
        'ready' => '준비 완료',
        _ => status,
      };
}

class RoomBoardCall {
  final String reason; // '' = 사유 없음
  final DateTime? at;
  const RoomBoardCall({this.reason = '', this.at});

  /// lib/models/staff_call_reason.dart(팀원 staff-call-reason 브랜치)·firestore.rules 목록과 같은 키
  static const labels = {
    'rule': '룰 설명',
    'swap': '게임 교체',
    'water': '물',
    'clean': '정리',
    'pay': '결제',
    'staff': '직원 호출',
  };
  String get label => labels[reason] ?? '직원 호출';
}

class RoomBoardEntry {
  final int room;
  final RoomBoardState state;
  final List<RoomBoardOrder> orders; // 진행 중 (오래된 것부터)
  final List<RoomBoardCall> calls;
  final List<OrderHistoryEntry> cycle; // 이번 손님 주문 (최근 것이 위)
  final int openCount; // 포스 결제 대기 주문 수
  final int total; // 이번 손님 주문 합계 (취소 뺌)
  final int unpaid; // 그중 결제 전
  final DateTime? firstAt; // 이번 손님 첫 주문 시각
  final DateTime? settledAt;
  final bool beyondCount; // 방 개수를 줄여서 범위 밖인데 기록이 남은 방
  final ({int paid, int unpaid})? posPayment; // 113차: 포스에서 일부만 결제됨
  final int? movedTo; // 114차: 포스 자리이동·합석으로 손님이 옮겨 간 방 (원래 방이 비었을 때)
  final ({int id, List<int> rooms})? group; // 114차 2: 포스 단체손님으로 묶인 방들 (표시만)

  const RoomBoardEntry({
    required this.room,
    required this.state,
    this.orders = const [],
    this.calls = const [],
    this.cycle = const [],
    this.openCount = 0,
    this.total = 0,
    this.unpaid = 0,
    this.firstAt,
    this.settledAt,
    this.beyondCount = false,
    this.posPayment,
    this.movedTo,
    this.group,
  });

  /// 114차: 이번 손님 주문이 모두 취소됨 (합계 0원인데 '결제됨'으로 보이지 않게)
  bool get allCancelled => cycle.isNotEmpty && cycle.every((e) => e.cancelled);

  int countOf(String status) => orders.where((o) => o.status == status).length;

  String get stateLabel => switch (state) {
        RoomBoardState.awaitingPay => '결제 대기',
        RoomBoardState.inUse => '이용 중',
        RoomBoardState.empty => '비어 있음',
      };
}

int? roomFromOrder(dynamic room) {
  final m = RegExp(r'(\d+)').firstMatch((room ?? '').toString());
  return m == null ? null : int.tryParse(m.group(1)!);
}

int _won(dynamic v) => int.tryParse((v ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

DateTime? _time(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  if (v is Timestamp) return v.toDate().toLocal();
  return DateTime.tryParse(v.toString())?.toLocal();
}

/// 방 현황판 목록 만들기 — 방 1~roomCount + 범위 밖이지만 기록이 있는 방
/// roomStatus: { '3': 문서 }, orders: 진행 중 주문 문서(+ 'id'), calls: 확인 안 한 호출 문서
List<RoomBoardEntry> buildRoomBoard({
  required int roomCount,
  Map<String, Map<String, dynamic>> roomStatus = const {},
  List<Map<String, dynamic>> orders = const [],
  List<Map<String, dynamic>> calls = const [],
}) {
  final ordersBy = <int, List<RoomBoardOrder>>{};
  for (final o in orders) {
    final room = roomFromOrder(o['room']);
    if (room == null || room < 1) continue;
    final items = o['items'];
    ordersBy.putIfAbsent(room, () => []).add(RoomBoardOrder(
          id: (o['id'] ?? '').toString(),
          status: (o['status'] ?? '').toString(),
          at: _time(o['timestamp']),
          items: items is List ? items.map((e) => e.toString()).toList() : const [],
          price: _won(o['price']),
        ));
  }
  for (final list in ordersBy.values) {
    list.sort((a, b) => (a.at ?? DateTime(9999)).compareTo(b.at ?? DateTime(9999)));
  }
  final callsBy = <int, List<RoomBoardCall>>{};
  for (final c in calls) {
    final v = c['roomNumber'];
    final room = v is num ? v.toInt() : int.tryParse('$v');
    if (room == null || room < 1) continue;
    callsBy.putIfAbsent(room, () => []).add(RoomBoardCall(reason: (c['reason'] ?? '').toString(), at: _time(c['timestamp'])));
  }
  final statusBy = <int, Map<String, dynamic>>{};
  roomStatus.forEach((k, v) {
    final n = int.tryParse(k);
    if (n != null && n >= 1) statusBy[n] = v;
  });

  final rooms = <int>{for (var i = 1; i <= roomCount; i++) i};
  // 범위 밖 방은 지금 진행 중인 것이 있을 때만 (지난 기록만 남은 방은 안 보임)
  for (final n in {...ordersBy.keys, ...callsBy.keys, ...statusBy.keys}) {
    if (n <= roomCount) continue;
    final s = statusBy[n];
    final busy = (ordersBy[n]?.isNotEmpty ?? false) ||
        (callsBy[n]?.isNotEmpty ?? false) ||
        ((s?['open'] as List?)?.isNotEmpty ?? false) ||
        ((s?['cycle'] as List?)?.isNotEmpty ?? false);
    if (busy) rooms.add(n);
  }

  final out = <RoomBoardEntry>[];
  for (final n in rooms.toList()..sort()) {
    final s = statusBy[n];
    final cycle = OrderHistoryEntry.listFrom(s);
    final totals = orderHistoryTotals(cycle);
    final openCount = s?['open'] is List ? (s!['open'] as List).length : 0;
    final roomOrders = ordersBy[n] ?? const <RoomBoardOrder>[];
    final roomCalls = callsBy[n] ?? const <RoomBoardCall>[];
    final state = openCount > 0
        ? RoomBoardState.awaitingPay
        : (cycle.isNotEmpty || roomOrders.isNotEmpty || roomCalls.isNotEmpty)
            ? RoomBoardState.inUse
            : RoomBoardState.empty;
    DateTime? first;
    for (final t in [...cycle.map((e) => e.at), ...roomOrders.map((o) => o.at)]) {
      if (t != null && (first == null || t.isBefore(first))) first = t;
    }
    out.add(RoomBoardEntry(
      room: n,
      state: state,
      orders: roomOrders,
      calls: roomCalls,
      cycle: cycle,
      openCount: openCount,
      total: totals.total,
      unpaid: totals.unpaid,
      firstAt: first,
      settledAt: _time(s?['settledAt']),
      beyondCount: n > roomCount,
      posPayment: roomPosPayment(s),
      movedTo: s?['movedTo'] is num ? (s!['movedTo'] as num).toInt() : null,
      group: roomGroupOf(s),
    ));
  }
  return out;
}

/// 114차 2: roomStatus.group {id, rooms} (서버가 포스 단체손님 묶음에서 씀)
({int id, List<int> rooms})? roomGroupOf(Map<String, dynamic>? s) {
  final g = s?['group'];
  if (g is! Map || g['id'] is! num) return null;
  final rooms = g['rooms'] is List
      ? [for (final r in g['rooms'] as List) if (r is num) r.toInt()]
      : <int>[];
  return (id: (g['id'] as num).toInt(), rooms: rooms);
}

/// 114차 2: 묶음마다 색 번호 — 가장 작은 방 번호 순서대로 0, 1, 2 …
Map<int, int> roomGroupColorIndex(List<RoomBoardEntry> board) {
  final firstRoom = <int, int>{};
  for (final e in board) {
    final g = e.group;
    if (g == null) continue;
    final r = firstRoom[g.id];
    if (r == null || e.room < r) firstRoom[g.id] = e.room;
  }
  final ids = firstRoom.keys.toList()..sort((a, b) => firstRoom[a]!.compareTo(firstRoom[b]!));
  return {for (var i = 0; i < ids.length; i++) ids[i]: i};
}

/// '35분째' / '1시간 5분째'
String roomElapsedLabel(DateTime since, DateTime now) {
  final m = now.difference(since).inMinutes;
  if (m < 1) return '방금';
  if (m < 60) return '$m분째';
  return '${m ~/ 60}시간${m % 60 == 0 ? '' : ' ${m % 60}분'}째';
}
