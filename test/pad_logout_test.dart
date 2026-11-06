import 'package:boardpad/models/home_layout.dart';
import 'package:boardpad/screens/login_screen.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/widgets/home/home_view.dart';
import 'package:boardpad/widgets/home_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 78차: 손님에게 보이는 '로그아웃 · 방 변경' 버튼은 지움 — 로그아웃은 로고 빠르게 10번(HoldToExit)만.
// 여기서는 그 뒤에 뜨는 확인 창·로그아웃 절차(showPadLogout)를 시험함.

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

/// 시험용: 누르면 로고 10번을 누른 것처럼 로그아웃 확인 창을 엶
class _OpenLogout extends StatelessWidget {
  final PadLogoutActions actions;
  const _OpenLogout({required this.actions});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showPadLogout(context, roomNumber: 2, actions: actions),
    child: const Text('창 열기'),
  );
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

  testWidgets('사이드바에 보이는 로그아웃 버튼이 없다', (tester) async {
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
            child: HomeSidebar(layout: layout, roomNumber: 2),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('로그아웃 · 방 변경'), findsNothing);
    expect(find.byIcon(Icons.logout), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('비밀번호가 틀리면 로그아웃하지 않는다', (tester) async {
    await sizeScreen(tester);
    final actions = TestLogoutActions();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _OpenLogout(actions: actions))),
    );
    await tester.tap(find.text('창 열기'));
    await tester.pumpAndSettle();
    expect(find.text('현재 방: 2번'), findsOneWidget);
    expect(find.text('비밀번호 또는 PIN'), findsOneWidget);
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
        builder: (_) => Scaffold(body: _OpenLogout(actions: actions)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('창 열기'));
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

  testWidgets('사이드바 내용이 길어도 화면을 넘치지 않는다', (tester) async {
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
            child: HomeSidebar(layout: layout, roomNumber: 2),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
