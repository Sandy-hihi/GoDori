import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/models/order_flow.dart';

void main() {
  group('OrderFlow (58차 음식 수령 방식)', () {
    test('모르는 값·없는 값은 서빙(예전 주문)', () {
      expect(OrderFlow.parse(null), OrderFlow.serve);
      expect(OrderFlow.parse('???'), OrderFlow.serve);
      expect(OrderFlow.parse('pickupPay'), OrderFlow.pickupPay);
    });

    test('서빙: 접수 → 준비중 → 완료 (ready 없음)', () {
      const f = OrderFlow.serve;
      expect(f.nextStatus('pending'), 'preparing');
      expect(f.nextStatus('preparing'), 'completed');
      expect(f.nextStatus('completed'), isNull);
      expect(f.cartNotice, isNull);
    });

    test('카운터 수령: 준비중 다음은 ready(패드 알림), 그다음 완료', () {
      for (final f in [OrderFlow.pickup, OrderFlow.pickupPay]) {
        expect(f.nextStatus('pending'), 'preparing');
        expect(f.nextStatus('preparing'), 'ready');
        expect(f.nextStatus('ready'), 'completed');
        expect(f.isPickup, isTrue);
      }
      expect(OrderFlow.pickup.payAtPickup, isFalse);
      expect(OrderFlow.pickupPay.payAtPickup, isTrue);
    });

    test('선결제 알림 문구에 금액', () {
      expect(OrderFlow.pickupPay.readyText('12000'), contains('12,000원'));
      expect(OrderFlow.pickup.readyText('12000'), isNot(contains('원')));
      expect(wonText('1500'), '1,500원');
    });
  });
}
