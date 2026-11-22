import 'package:boardpad/main.dart';
import 'package:boardpad/screens/login_screen.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpStartup(WidgetTester tester, Future<PadSession?> Function() restore) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StartupScreen(restoreSession: restore)));
    // 143차: 오류 화면은 1초마다 남은 초를 고쳐서 pumpAndSettle 대신 pump
    await tester.pump();
    await tester.pump();
  }

  testWidgets('로그인 복원 통신 실패 시 인터넷 끊김 화면 → 다시 시도하면 화면을 진행한다', (tester) async {
    var attempts = 0;
    await pumpStartup(tester, () async {
      attempts++;
      if (attempts == 1) throw SessionRestoreException();
      return null;
    });
    expect(find.text('인터넷 연결이 끊겼어요'), findsOneWidget);
    expect(find.textContaining('저장된 로그인 정보를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('15초 뒤에 자동으로 다시 시도해요'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('인터넷 끊김 화면은 15초 뒤 저절로 다시 시도한다', (tester) async {
    var attempts = 0;
    await pumpStartup(tester, () async {
      attempts++;
      if (attempts == 1) throw AdminNetworkException('로그인 서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
      return null;
    });
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('10초 뒤에 자동으로 다시 시도해요'), findsOneWidget);
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('인터넷 문제가 아닌 오류는 저절로 다시 시도하지 않는다', (tester) async {
    var attempts = 0;
    await pumpStartup(tester, () async {
      attempts++;
      throw AdminLoginException('로그인이 풀렸어요. 직원에게 패드 로그인을 부탁해 주세요.');
    });
    expect(find.text('잠시 문제가 생겼어요'), findsOneWidget);
    expect(find.textContaining('초 뒤에 자동으로'), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(attempts, 1);
  });
}
