import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/models/party_session.dart';
import 'package:boardpad/screens/party_screen.dart';
import 'package:boardpad/services/party_session_store.dart';

class MemorySessionStore implements PartySessionStore {
  final Map<int?, String> data = {};
  bool failSave = false;
  @override
  Future<PartySession> load(int? roomNumber) async => data[roomNumber] == null
      ? PartySession()
      : PartySession.fromJson(
          jsonDecode(data[roomNumber]!) as Map<String, dynamic>,
        );
  @override
  Future<void> save(int? roomNumber, PartySession session) async {
    if (failSave) throw StateError('저장 실패');
    data[roomNumber] = jsonEncode(session.toJson());
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    MemorySessionStore store, {
    int room = 1,
  }) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PartyScreen(
          roomNumber: room,
          store: store,
          menuCatalog: Future.value([
            {'id': 'coffee', 'name': '아메리카노', 'price': 3000},
          ]),
          catalog: Future.value([
            {'title': '두 명 게임', 'players': '2인전용'},
            {'title': '네 명 게임', 'players': '3~4명', 'isRecommended': true},
            {'title': '다섯 명 게임', 'players': '5~8명'},
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('메뉴 선택을 저장하고 직접 입력으로 전환하면 주문 연결을 해제한다', (tester) async {
    final store = MemorySessionStore();
    await store.save(
      1,
      PartySession(players: ['도리', '민수'], cafe: '카페', drink: '음료'),
    );
    await open(tester, store);
    await tester.tap(find.text('승패 · 음료 내기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('주문 메뉴에서 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('아메리카노 · 3000원').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('일행과 내기 저장'));
    await tester.tap(find.text('일행과 내기 저장'));
    await tester.pumpAndSettle();
    expect((await store.load(1)).menuId, 'coffee');
    expect((await store.load(1)).drink, '아메리카노');
    expect(find.text('선택 메뉴 주문하기'), findsOneWidget);
    await tester.ensureVisible(find.text('직접 입력'));
    await tester.tap(find.text('직접 입력'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('일행과 내기 저장'));
    await tester.tap(find.text('일행과 내기 저장'));
    await tester.pumpAndSettle();
    expect((await store.load(1)).menuId, isNull);
    expect(find.text('선택 메뉴 주문하기'), findsNothing);
  });

  testWidgets('입력 인원에 맞는 게임만 추천한다', (tester) async {
    await open(tester, MemorySessionStore());
    expect(find.text('네 명 게임'), findsOneWidget);
    expect(find.text('두 명 게임'), findsNothing);
    expect(find.text('다섯 명 게임'), findsNothing);
    final input = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '인원 수',
    );
    await tester.enterText(input, '2');
    await tester.tap(find.text('인원에 맞는 게임 추천'));
    await tester.pumpAndSettle();
    expect(find.text('두 명 게임'), findsOneWidget);
    expect(find.text('네 명 게임'), findsNothing);
    await tester.enterText(input, '0');
    await tester.tap(find.text('인원에 맞는 게임 추천'));
    await tester.pumpAndSettle();
    expect(find.text('1~100명 사이의 인원을 입력하세요.'), findsOneWidget);
  });

  testWidgets('승패를 저장하고 재진입하면 방별로 복원된다', (tester) async {
    final store = MemorySessionStore();
    await store.save(
      1,
      PartySession(players: ['도리', '민수'], cafe: '카페', drink: '음료 한 잔씩'),
    );
    await open(tester, store);
    await tester.tap(find.text('승패 · 음료 내기'));
    await tester.pumpAndSettle();
    final gameInput = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '게임 이름 · 직접 입력 가능',
    );
    await tester.enterText(gameInput, '두 명 게임');
    await tester.tap(find.byKey(const ValueKey('outcome_도리_승')));
    await tester.tap(find.byKey(const ValueKey('outcome_민수_패')));
    final save = find.text('이 판의 승패 저장');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await store.load(1)).drinkWinners, ['민수']);
    expect((await store.load(1)).rounds.single.game, '두 명 게임');
    expect((await store.load(2)).rounds, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await open(tester, store);
    await tester.tap(find.text('승패 · 음료 내기'));
    await tester.pumpAndSettle();
    expect(find.text('현재 음료 내기 당첨: 민수'), findsOneWidget);
  });

  testWidgets('저장 실패는 이전 기록을 유지하고 오류를 알린다', (tester) async {
    final store = MemorySessionStore();
    await store.save(
      1,
      PartySession(players: ['도리', '민수'], cafe: '카페', drink: '음료'),
    );
    store.failSave = true;
    await open(tester, store);
    await tester.tap(find.text('승패 · 음료 내기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '게임 이름 · 직접 입력 가능',
      ),
      '게임',
    );
    await tester.tap(find.byKey(const ValueKey('outcome_도리_승')));
    await tester.tap(find.byKey(const ValueKey('outcome_민수_패')));
    await tester.ensureVisible(find.text('이 판의 승패 저장'));
    await tester.tap(find.text('이 판의 승패 저장'));
    await tester.pumpAndSettle();
    expect((await store.load(1)).rounds, isEmpty);
    expect(find.text('저장하지 못했습니다. 기존 기록은 유지됩니다. 다시 시도해주세요.'), findsOneWidget);
  });

  testWidgets('내기를 정하지 않아도 밸런스 선택으로 팀을 나눈다', (tester) async {
    final store = MemorySessionStore();
    await store.save(1, PartySession(players: ['도리', '민수']));
    await open(tester, store);
    await tester.tap(find.text('밸런스 게임 · 팀'));
    await tester.pumpAndSettle();
    final teamButton = find.widgetWithText(FilledButton, 'A/B 선택으로 팀 나누기');
    expect(tester.widget<FilledButton>(teamButton).onPressed, isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, 'A').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'B').last);
    await tester.pump();
    expect(find.text('선택 완료: 2 / 2명'), findsOneWidget);
    expect(tester.widget<FilledButton>(teamButton).onPressed, isNotNull);
    await tester.tap(teamButton);
    await tester.pumpAndSettle();
    expect(find.text('A팀 · 1명'), findsOneWidget);
    expect(find.text('B팀 · 1명'), findsOneWidget);
    await tester.tap(find.text('다음 랜덤 질문'));
    await tester.pumpAndSettle();
    expect(find.text('선택 완료: 0 / 2명'), findsOneWidget);
    expect(find.text('A팀 · 1명'), findsNothing);
  });
}
