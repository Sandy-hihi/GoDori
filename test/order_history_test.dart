import 'package:flutter_test/flutter_test.dart';

import 'package:boardpad/models/order_history.dart';

// 84차 손님 패드 '주문 내역' — roomStatus.cycle 읽기
void main() {
  test('cycle → 최근 주문이 위로, 잘못된 항목은 건너뜀', () {
    final list = OrderHistoryEntry.listFrom({
      'cycle': [
        {
          'id': 'a',
          'at': '2026-11-08T08:05:00.000Z',
          'price': '11500',
          'lines': [
            {'menuId': 'm1', 'name': '아메리카노', 'quantity': 2, 'options': ['ICE', '']},
            {'name': ''},
          ],
          'state': 'paid',
        },
        'garbage',
        {'id': ''},
        {'id': 'b', 'price': 5000, 'items': ['라면 x 1'], 'state': '??'},
      ],
    });
    expect(list.map((e) => e.id), ['b', 'a']);
    expect(list[0].state, 'open');
    expect(list[0].price, 5000);
    expect(list[0].lines, isEmpty);
    expect(list[0].items, ['라면 x 1']);
    expect(list[1].paid, isTrue);
    expect(list[1].at, isNotNull);
    expect(list[1].lines.single.quantity, 2);
    expect(list[1].lines.single.options, ['ICE']);
  });

  test('문서가 없거나 cycle이 없으면 빈 목록', () {
    expect(OrderHistoryEntry.listFrom(null), isEmpty);
    expect(OrderHistoryEntry.listFrom({'open': []}), isEmpty);
  });

  test('합계: 취소 빼고, 결제 전 금액 따로', () {
    final t = orderHistoryTotals(const [
      OrderHistoryEntry(id: 'a', price: 3000, state: 'paid'),
      OrderHistoryEntry(id: 'b', price: 5000),
      OrderHistoryEntry(id: 'c', price: 9000, state: 'cancelled'),
    ]);
    expect(t.total, 8000);
    expect(t.unpaid, 5000);
  });

  test('준비 상태 글자', () {
    expect(orderHistoryStatusText('pending'), '주문 접수');
    expect(orderHistoryStatusText('preparing'), '준비 중');
    expect(orderHistoryStatusText('ready'), '준비 완료');
    expect(orderHistoryStatusText('completed'), '전달 완료');
    expect(orderHistoryStatusText(null), '전달 완료');
  });
}
