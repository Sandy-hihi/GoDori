import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/l10n/guest_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GuestLanguage.instance.select('ko');
  });
  test('all interface messages have three nonempty translations', () {
    for (final entry in guestMessages.entries) {
      expect(entry.value.length, 3, reason: entry.key);
      expect(
        entry.value.every((text) => text.trim().isNotEmpty),
        isTrue,
        reason: entry.key,
      );
    }
  });
  test('selection persists and unsupported languages are ignored', () async {
    await GuestLanguage.instance.select('ja');
    expect(
      (await SharedPreferences.getInstance()).getString('guest_language'),
      'ja',
    );
    await GuestLanguage.instance.select('unsupported');
    expect(GuestLanguage.instance.code, 'ja');
    await GuestLanguage.instance.load();
    expect(GuestLanguage.instance.code, 'ja');
  });
  testWidgets('language changes update labels and retain field state', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Dori');
    await tester.pumpWidget(
      MaterialApp(
        home: GuestLocaleScope(
          child: Scaffold(
            body: Column(
              children: [
                const GuestText('주문하기'),
                TextField(controller: controller),
                Builder(
                  builder: (context) => TextField(
                    decoration: InputDecoration(
                      labelText: guestTr(context, '참가자 이름'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (final row in [
      ('en', 'Place order', 'Player names'),
      ('zh', '下单', '参与者姓名'),
      ('ja', '注文する', '参加者名'),
    ]) {
      await GuestLanguage.instance.select(row.$1);
      await tester.pump();
      expect(find.text(row.$2), findsOneWidget);
      expect(find.text(row.$3), findsOneWidget);
      expect(controller.text, 'Dori');
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'catalog translations use selected language with original fallback',
    (tester) async {
      await GuestLanguage.instance.select('en');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(
                guestField(context, {
                  'title': '원문',
                  'translations': {
                    'en': {'title': 'Translated'},
                  },
                }, 'title'),
                'Translated',
              );
              expect(guestField(context, {'title': '원문'}, 'title'), '원문');
              return const SizedBox();
            },
          ),
        ),
      );
    },
  );

  // 81차: 시계·매장 글
  test('clock date and time are translated', () async {
    final l = GuestLanguage.instance;
    await l.select('en');
    expect(l.translate('11월 7일 (토)'), 'Sat, Nov 7');
    expect(l.translate('오후 10:01'), '10:01 PM');
    expect(l.translate('오전 9:05'), '9:05 AM');
    await l.select('zh');
    expect(l.translate('11월 7일 (토)'), '11月7日（周六）');
    expect(l.translate('오후 10:01'), '下午10:01');
    await l.select('ja');
    expect(l.translate('11월 7일 (토)'), '11月7日（土）');
    expect(l.translate('오전 9:05'), '午前9:05');
    await l.select('ko');
    expect(l.translate('오후 10:01'), '오후 10:01');
  });
  test('store text is translated only on exact match', () async {
    final l = GuestLanguage.instance;
    await l.select('en');
    expect(l.translateExact('이용안내'), guestMessages['이용안내']![0]);
    expect(l.translateExact('안녕하세요!'), 'Hello!');
    expect(l.translateExact('우리 매장 3번 공지'), '우리 매장 3번 공지');
    await l.select('ko');
    expect(l.translateExact('이용안내'), '이용안내');
  });

  // 81차: 로그인 때 언어 = 기본 언어, 방 결제 끝나면 되돌림
  test('default language is remembered at login and restored', () async {
    final l = GuestLanguage.instance;
    await l.select('en');
    await l.rememberDefault();
    await l.select('ja');
    await l.load();
    expect(l.code, 'ja');
    expect(l.defaultCode, 'en');
    await l.resetToDefault();
    expect(l.code, 'en');
    expect(
      (await SharedPreferences.getInstance()).getString('guest_language'),
      'en',
    );
  });

  // 91차(DEF-007): 패드 로그인 오류 문구 — 서버·앱 문구 그대로, 숫자 섞인 것은 규칙으로
  test('pad login error messages are translated', () async {
    final l = GuestLanguage.instance;
    await l.select('en');
    expect(l.translate('아이디 또는 비밀번호가 올바르지 않습니다.'), 'Incorrect ID or password.');
    expect(l.translate('비밀번호를 입력해 주세요.'), 'Please enter the password.');
    expect(l.translate('이 매장의 방 번호는 1~11번이에요. (관리자는 0)'),
        'Room numbers for this store are 1–11. (Admin: 0)');
    await l.select('ja');
    expect(l.translate('요청을 처리하지 못했어요. (418)'), 'リクエストを処理できませんでした。（418）');
  });
}
