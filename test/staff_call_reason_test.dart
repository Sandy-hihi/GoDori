import 'dart:io';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/l10n/guest_messages.dart';
import 'package:boardpad/models/staff_call_reason.dart';
import 'package:boardpad/services/staff_call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GuestLanguage.instance.select('ko');
  });

  test('reason keys are unique and unknown values fall back to null', () {
    final keys = staffCallReasons.map((r) => r.key).toList();
    expect(keys.toSet().length, keys.length);
    expect(staffCallReasonOf('rule')?.label, '게임 설명');
    expect(staffCallReasonOf(null), isNull); // 예전 호출 (사유 없음)
    expect(staffCallReasonOf('unknown'), isNull);
    expect(staffCallReasonOf(3), isNull);
  });

  test('every reason label and hint is translated for guests', () {
    for (final r in staffCallReasons) {
      expect(guestMessages.containsKey(r.label), isTrue, reason: r.label);
      expect(guestMessages.containsKey(r.hint), isTrue, reason: r.hint);
    }
  });

  test('firestore.rules allows exactly the same reason keys as the app', () {
    final rules = File('firestore.rules').readAsStringSync();
    final match = RegExp(r"request\.resource\.data\.reason in \[([^\]]*)\]").firstMatch(rules);
    expect(match, isNotNull, reason: 'staff_calls 규칙에 reason 허용 목록이 있어야 함');
    final allowed = RegExp(r"'([^']+)'").allMatches(match!.group(1)!).map((m) => m.group(1)!).toSet();
    expect(allowed, staffCallReasons.map((r) => r.key).toSet());
  });

  Future<void> pumpDialog(WidgetTester tester, Future<void> Function(StaffCallReason) onSend) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StaffCallDialog(onSend: onSend))));
  }

  testWidgets('tapping a reason sends it once and shows the confirmation', (tester) async {
    final sent = <String>[];
    await pumpDialog(tester, (r) async => sent.add(r.key));

    for (final r in staffCallReasons) {
      expect(find.text(r.label), findsOneWidget);
    }
    expect(find.text('직원에게 전달했어요. 잠시만 기다려 주세요.'), findsNothing);

    await tester.tap(find.text('게임 설명'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent, ['rule']);
    expect(find.text('직원에게 전달했어요. 잠시만 기다려 주세요.'), findsOneWidget);

    // 같은 사유는 다시 눌러도 또 보내지 않음 (타일의 글자는 그대로, 알림 줄에도 같은 글자가 하나 더 있음)
    await tester.tap(find.text('게임 설명').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent, ['rule']);

    // 다른 사유는 이어서 보낼 수 있음
    await tester.tap(find.text('물·컵'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent, ['rule', 'water']);
  });

  testWidgets('a failed call shows an error and can be retried', (tester) async {
    var attempts = 0;
    await pumpDialog(tester, (r) async {
      attempts++;
      if (attempts == 1) throw Exception('offline');
    });

    await tester.tap(find.text('테이블 정리'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('직원 호출을 보내지 못했어요. 인터넷 연결을 확인해 주세요.'), findsOneWidget);
    expect(find.text('직원에게 전달했어요. 잠시만 기다려 주세요.'), findsNothing);

    await tester.tap(find.text('테이블 정리'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(attempts, 2);
    expect(find.text('직원 호출을 보내지 못했어요. 인터넷 연결을 확인해 주세요.'), findsNothing);
    expect(find.text('직원에게 전달했어요. 잠시만 기다려 주세요.'), findsOneWidget);
  });
}
