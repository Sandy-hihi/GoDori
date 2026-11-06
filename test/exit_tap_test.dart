import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/widgets/home_common.dart';

// 패드 로그아웃 창 여는 방법(56차): 로고를 빠르게 10번 누르기
Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(
      body: Center(child: HoldToExit(child: SizedBox(width: 120, height: 60, child: Text('로고')))),
    ),
  ));
}

Future<void> _tapTimes(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.tap(find.text('로고'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('9번 누르면 아무 일 없음', (tester) async {
    await _open(tester);
    await _tapTimes(tester, 9);
    await tester.pumpAndSettle();
    expect(find.text('패드 로그아웃'), findsNothing);
  });

  testWidgets('빠르게 10번 누르면 로그아웃 창, 닫기로 닫힘', (tester) async {
    await _open(tester);
    await _tapTimes(tester, 10);
    await tester.pumpAndSettle();
    expect(find.text('패드 로그아웃'), findsOneWidget);
    expect(find.text('비밀번호 또는 PIN'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('패드 로그아웃'), findsNothing);
  });

  // 62차: 연타가 넘쳐 11~13번째 터치가 창 바깥(어두운 배경)에 닿아도 창이 그대로 있어야 함.
  // 2초가 지난 뒤 바깥을 누르면 닫힘
  testWidgets('10번 넘게 눌러도 안 닫히고, 2초 뒤 바깥을 누르면 닫힘', (tester) async {
    await _open(tester);
    await _tapTimes(tester, 13);
    await tester.pumpAndSettle();
    expect(find.text('패드 로그아웃'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // 2초 전 바깥 터치 → 그대로
    await tester.pumpAndSettle();
    expect(find.text('패드 로그아웃'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.tapAt(const Offset(5, 5)); // 2초 뒤 바깥 터치 → 닫힘
    await tester.pumpAndSettle();
    expect(find.text('패드 로그아웃'), findsNothing);
  });
}
