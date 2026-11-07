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
}
