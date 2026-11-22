import 'package:boardpad/widgets/pad_idle_home.dart';
import 'package:flutter_test/flutter_test.dart';

// 140차: 토스 연동 안 한 매장은 30분 동안 안 만지면 홈으로
void main() {
  final t0 = DateTime(2026, 11, 22, 14);
  bool go({
    Duration after = const Duration(minutes: 30),
    bool guestPad = true,
    bool? tossPos = false,
    bool held = false,
  }) =>
      PadIdleHome.shouldGoHome(lastActivity: t0, now: t0.add(after), guestPad: guestPad, tossPos: tossPos, held: held);

  test('30분이 지나면 홈으로, 그 전엔 그대로', () {
    expect(go(), isTrue);
    expect(go(after: const Duration(minutes: 29, seconds: 59)), isFalse);
    expect(go(after: const Duration(hours: 3)), isTrue);
  });

  test('토스 연동 매장·연동 여부 모름·관리자 패드·로그인 전에는 안 함', () {
    expect(go(tossPos: true), isFalse);
    expect(go(tossPos: null), isFalse);
    expect(go(guestPad: false), isFalse);
  });

  test('타이머·스톱워치·영상이 돌면 기다림', () {
    expect(go(held: true), isFalse);
  });
}
