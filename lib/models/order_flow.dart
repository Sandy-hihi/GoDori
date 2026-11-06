/// 음식 수령 방식 (58차) — 매장마다 다름. Firebase 없이 쓰는 순수 로직이라 테스트에서 바로 씀.
///
/// - serve     : 음식이 준비되면 직원이 방으로 가져다 드림 (플랫폼6, 설정이 없을 때 기본값)
/// - pickup    : 준비되면 방 패드에 알림 → 손님이 카운터로 와서 받아 감 (계산은 나갈 때)
/// - pickupPay : 준비되면 방 패드에 알림 → 손님이 카운터에서 결제하고 받아 감 (선결제)
///
/// 주문 상태(orders.status)
///   serve     : pending(접수) → preparing(준비중) → completed(서빙 완료)
///   pickup    : pending → preparing → ready(준비 완료 — 패드 알림) → completed(받아 감)
///   pickupPay : pending → preparing → ready → completed(결제·전달 완료, paid: true)
/// 주문을 넣을 때의 방식을 주문 문서(flow)에 같이 저장 → 영업 중에 설정을 바꿔도 이미 들어온 주문은 그대로 흘러감.
/// flow가 없는 예전 주문은 serve로 봄.
enum OrderFlow {
  serve('serve'),
  pickup('pickup'),
  pickupPay('pickupPay');

  final String id;
  const OrderFlow(this.id);

  static const OrderFlow fallback = OrderFlow.serve;

  static OrderFlow parse(Object? v) {
    for (final f in OrderFlow.values) {
      if (f.id == v) return f;
    }
    return fallback;
  }

  /// 손님이 카운터로 와야 하는 방식인가
  bool get isPickup => this != OrderFlow.serve;

  /// 받을 때 결제하는 방식인가
  bool get payAtPickup => this == OrderFlow.pickupPay;

  // ── 관리자 웹 '매장 설정' 문구 ──
  String get title => switch (this) {
        OrderFlow.serve => '방으로 가져다 드려요',
        OrderFlow.pickup => '손님이 카운터에서 받아 가요',
        OrderFlow.pickupPay => '손님이 카운터에서 결제하고 받아 가요',
      };

  String get description => switch (this) {
        OrderFlow.serve => '음식이 준비되면 직원이 방까지 가져다 드려요. 계산은 나갈 때 한 번에.',
        OrderFlow.pickup => '주문현황에서 \'준비 완료\'를 누르면 그 방 패드에 알림이 떠요. 손님이 카운터로 가지러 와요. 계산은 나갈 때 한 번에.',
        OrderFlow.pickupPay => '\'준비 완료\'를 누르면 그 방 패드에 알림이 떠요. 손님이 카운터에서 음식값을 결제하고 받아 가요.',
      };

  /// 주문현황 카드의 작은 표시
  String get badge => switch (this) {
        OrderFlow.serve => '서빙',
        OrderFlow.pickup => '카운터 수령',
        OrderFlow.pickupPay => '수령 때 결제',
      };

  // ── 손님 패드 문구 ──
  /// 장바구니 '주문하기' 위 안내 (없으면 null)
  String? get cartNotice => switch (this) {
        OrderFlow.serve => null,
        OrderFlow.pickup => '준비되면 패드로 알려 드려요. 카운터에서 받아 가 주세요.',
        OrderFlow.pickupPay => '준비되면 패드로 알려 드려요. 카운터에서 결제하고 받아 가 주세요.',
      };

  /// 주문 접수 창의 둘째 줄
  String get orderDoneText => switch (this) {
        OrderFlow.serve => '준비되면 자리로 가져다드릴게요.',
        OrderFlow.pickup => '준비되면 패드에 알림이 떠요.\n그때 카운터로 받으러 와 주세요.',
        OrderFlow.pickupPay => '준비되면 패드에 알림이 떠요.\n카운터에서 결제하고 받아 가 주세요.',
      };

  /// 준비 완료 알림 본문
  String readyText(String price) => switch (this) {
        OrderFlow.serve => '곧 자리로 가져다드릴게요.',
        OrderFlow.pickup => '카운터로 받으러 와 주세요.',
        OrderFlow.pickupPay => price.isEmpty
            ? '카운터에서 결제하고 받아 가 주세요.'
            : '카운터에서 ${wonText(price)}을 결제하고 받아 가 주세요.',
      };

  // ── 주문현황(관리자 패드) 상태 흐름 ──
  /// 지금 상태에서 다음 상태 (completed면 null — 그다음은 삭제)
  String? nextStatus(String status) {
    switch (status) {
      case 'pending':
        return 'preparing';
      case 'preparing':
        return isPickup ? 'ready' : 'completed';
      case 'ready':
        return 'completed';
    }
    return null;
  }

  /// 지금 상태일 때 오른쪽 버튼 글자 (누르면 nextStatus로)
  String buttonLabel(String status) {
    switch (status) {
      case 'pending':
        return '준비 시작';
      case 'preparing':
        return isPickup ? '준비 완료\n(패드 알림)' : '서빙 완료';
      case 'ready':
        return payAtPickup ? '결제·전달\n완료' : '받아 감';
    }
    return '삭제';
  }

  /// 카드 왼쪽 아래 상태 글자
  String statusText(String status) {
    switch (status) {
      case 'pending':
        return '새 주문';
      case 'preparing':
        return '준비중';
      case 'ready':
        return payAtPickup ? '결제 대기' : '수령 대기';
      case 'completed':
        return isPickup ? (payAtPickup ? '결제·전달 끝' : '전달 끝') : '서빙 끝';
    }
    return status;
  }
}

/// '12000' → '12,000원'
String wonText(String price) {
  final digits = price.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return price;
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '$buf원';
}
