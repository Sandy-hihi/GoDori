import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:boardpad/screens/login_screen.dart';

// 태블릿 가로 화면(1280×800 기준)보다 넉넉하게 — 로그인 카드가 화면 안에 다 들어오게
Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('로그인 화면: 아이디·비밀번호·방 번호 칸과 자동 로그인', (tester) async {
    await _open(tester);
    expect(find.text('매장 아이디'), findsOneWidget);
    expect(find.text('비밀번호'), findsOneWidget);
    expect(find.text('방 번호'), findsOneWidget);
    // 손님 방은 자동 로그인 기본 켜짐
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
  });

  testWidgets('방 번호 0이면 관리자 안내가 나오고 자동 로그인이 꺼짐', (tester) async {
    await _open(tester);
    await tester.enterText(find.widgetWithText(TextField, '방 번호'), '0');
    await tester.pump();
    expect(find.textContaining('0 = 관리자 대시보드'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
    // 다시 손님 방 번호로 바꾸면 켜짐
    await tester.enterText(find.widgetWithText(TextField, '방 번호'), '3');
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
  });

  testWidgets('빈 칸으로 로그인하면 서버를 부르지 않고 안내', (tester) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pump();
    expect(find.text('매장 아이디, 비밀번호, 방 번호를 모두 입력해 주세요.'), findsOneWidget);
  });
}
