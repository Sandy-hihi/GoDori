/// 손님 패드 '주문 내역' (84차) — roomStatus/{방}.cycle 을 읽어 화면에 보여줄 모양으로
///
/// 서버(functions/src/toss-data.js cycleEntry)가 포스로 들어간 주문을 요약해 넣고,
/// 포스에서 결제되면 state 'paid', 취소되면 'cancelled'. 방 전체 결제가 끝나면(settledAt) 비움.
/// 그래서 토스 POS 연동 매장에서만 씀 (features.tossPos).
library;

class OrderHistoryLine {
  final String menuId;
  final String name;
  final int quantity;
  final List<String> options;

  const OrderHistoryLine({required this.menuId, required this.name, required this.quantity, this.options = const []});

  static OrderHistoryLine? fromAny(dynamic raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString();
    if (name.isEmpty) return null;
    final q = raw['quantity'];
    final quantity = q is num ? q.toInt() : int.tryParse('$q') ?? 1;
    final opts = raw['options'];
    return OrderHistoryLine(
      menuId: (raw['menuId'] ?? '').toString(),
      name: name,
      quantity: quantity < 1 ? 1 : quantity,
      options: opts is List ? opts.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() : const [],
    );
  }
}

class OrderHistoryEntry {
  final String id;
  final DateTime? at;
  final int price; // 원
  final List<String> items; // 옛 표시용 글자 ('아메리카노 (ICE) x 1') — lines가 없을 때만 씀
  final List<OrderHistoryLine> lines;
  final String state; // 'open' | 'paid' | 'cancelled'

  const OrderHistoryEntry({
    required this.id,
    this.at,
    this.price = 0,
    this.items = const [],
    this.lines = const [],
    this.state = 'open',
  });

  bool get paid => state == 'paid';
  bool get cancelled => state == 'cancelled';

  static OrderHistoryEntry? fromAny(dynamic raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    if (id.isEmpty) return null;
    final digits = (raw['price'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    final items = raw['items'];
    final lines = raw['lines'];
    final state = (raw['state'] ?? 'open').toString();
    return OrderHistoryEntry(
      id: id,
      at: DateTime.tryParse((raw['at'] ?? '').toString())?.toLocal(),
      price: int.tryParse(digits) ?? 0,
      items: items is List ? items.map((e) => e.toString()).toList() : const [],
      lines: lines is List ? lines.map(OrderHistoryLine.fromAny).whereType<OrderHistoryLine>().toList() : const [],
      state: const ['open', 'paid', 'cancelled'].contains(state) ? state : 'open',
    );
  }

  /// roomStatus 문서 → 최근 주문이 위로
  static List<OrderHistoryEntry> listFrom(Map<String, dynamic>? roomStatus) {
    final raw = roomStatus?['cycle'];
    if (raw is! List) return const [];
    return raw.map(fromAny).whereType<OrderHistoryEntry>().toList().reversed.toList();
  }
}

/// 합계 — 취소 뺀 전체, 그중 아직 결제 안 한 금액
({int total, int unpaid}) orderHistoryTotals(List<OrderHistoryEntry> list) {
  var total = 0, unpaid = 0;
  for (final e in list) {
    if (e.cancelled) continue;
    total += e.price;
    if (!e.paid) unpaid += e.price;
  }
  return (total: total, unpaid: unpaid);
}

/// 손님에게 보여줄 준비 상태 (주문 문서 status). 진행 중 목록에 없으면(완료·삭제) 'done'
/// pending → 주문 접수 / preparing → 준비 중 / ready → 준비 완료 / 그 외 → 전달 완료
String orderHistoryStatusText(String? status) {
  switch (status) {
    case 'pending':
      return '주문 접수';
    case 'preparing':
      return '준비 중';
    case 'ready':
      return '준비 완료';
  }
  return '전달 완료';
}
