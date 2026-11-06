import 'package:boardpad/models/home_layout.dart';
import 'package:boardpad/screens/login_screen.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/widgets/home/home_view.dart';
import 'package:boardpad/widgets/home_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestLogoutActions extends PadLogoutActions {
  int signOutCount = 0;
  final List<String> passwords = [];

  @override
  Future<void> verifyPassword(String password) async {
    passwords.add(password);
    if (password != 'test-password') {
      throw AdminLoginException('비밀번호가 올바르지 않습니다.');
    }
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    await super.signOut();
  }
}

Future<void> sizeScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'login.storeId': 'platform6',
      'login.room': 2,
      'login.autoLogin': true,
    });
    StoreScope.set('platform6');
  });
  tearDown(StoreScope.clear);

  testWidgets('로고가 없는 사이드바에도 로그아웃 버튼이 있다', (tester) async {
    await sizeScreen(tester);
    final layout = HomeLayout.defaults().copyWith(
      sidebarItems: const [
        SidebarItem('links', {'targets': []}),
        SidebarItem('spacer'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: HomeLayout.sidebarWidth,
            height: 800,
            child: HomeSidebar(
              layout: layout,
              roomNumber: 2,
              enableLogout: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('로그아웃 · 방 변경'), findsOneWidget);
    await tester.tap(find.text('로그아웃 · 방 변경'));
    await tester.pumpAndSettle();
    expect(find.text('현재 방: 2번'), findsOneWidget);
    expect(find.text('비밀번호 또는 PIN'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect((await AdminSession.loadPrefs()).autoLogin, isTrue);
    expect(StoreScope.isSet, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('비밀번호가 틀리면 로그아웃하지 않는다', (tester) async {
    await sizeScreen(tester);
    final actions = TestLogoutActions();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PadLogoutButton(roomNumber: 2, actions: actions)),
      ),
    );
    await tester.tap(find.text('로그아웃 · 방 변경'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong-password');
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(find.text('비밀번호가 올바르지 않습니다.'), findsOneWidget);
    expect(actions.signOutCount, 0);
    expect(StoreScope.isSet, isTrue);
    expect((await AdminSession.loadPrefs()).autoLogin, isTrue);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
  });

  testWidgets('로그아웃하면 자동 로그인을 풀고 이전 방으로 돌아가지 못한다', (tester) async {
    await sizeScreen(tester);
    final actions = TestLogoutActions();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('이전 방 홈')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            Scaffold(body: PadLogoutButton(roomNumber: 2, actions: actions)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃 · 방 변경'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test-password');
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(actions.signOutCount, 1);
    expect(StoreScope.isSet, isFalse);
    expect((await AdminSession.loadPrefs()).autoLogin, isFalse);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(find.text('이전 방 홈'), findsNothing);
    final roomField = find.widgetWithText(TextField, '방 번호');
    expect(tester.widget<TextField>(roomField).controller!.text, '2');
    await tester.enterText(roomField, '3');
    expect(tester.widget<TextField>(roomField).controller!.text, '3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('관리자 미리보기의 로그아웃 버튼은 동작하지 않는다', (tester) async {
    await sizeScreen(tester);
    final layout = HomeLayout.defaults().copyWith(
      sidebarItems: const [SidebarItem('spacer')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: HomeLayout.sidebarWidth,
            height: 800,
            child: HomeSidebar(layout: layout, roomNumber: 7),
          ),
        ),
      ),
    );
    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('사이드바 내용이 길어도 로그아웃 버튼은 화면 안에 남는다', (tester) async {
    await sizeScreen(tester);
    final layout = HomeLayout.defaults().copyWith(
      sidebarItems: [
        for (var i = 0; i < 15; i++)
          const SidebarItem('note', {'text': '안내 문구'}),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: HomeLayout.sidebarWidth,
            height: 800,
            child: HomeSidebar(
              layout: layout,
              roomNumber: 2,
              enableLogout: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('로그아웃 · 방 변경').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
