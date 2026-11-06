import 'package:boardpad/main.dart';
import 'package:boardpad/screens/login_screen.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('로그인 복원 통신 실패 시 다시 시도하고 화면을 진행한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;
    Future<PadSession?> restore() async {
      attempts++;
      if (attempts == 1) throw SessionRestoreException();
      return null;
    }

    await tester.pumpWidget(
      MaterialApp(home: StartupScreen(restoreSession: restore)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('저장된 로그인 정보를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
