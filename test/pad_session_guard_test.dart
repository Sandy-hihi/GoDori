import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/widgets/pad_session_guard.dart';
import 'package:boardpad/services/translation_overrides.dart';

// 120차: 비밀번호를 바꾸면 패드 강제 로그아웃 — 로그인 시각(초) vs 바꾼 시각(ms)
void main() {
  test('비밀번호를 바꾸기 전에 로그인한 패드만 로그아웃', () {
    const changedMs = 1700000000500;
    expect(PadSessionGuard.isStale(authTimeSec: 1699999990, epochMs: changedMs), isTrue);
    // 바꾼 바로 그 초에 새로 로그인한 패드는 그대로
    expect(PadSessionGuard.isStale(authTimeSec: 1700000000, epochMs: changedMs), isFalse);
    expect(PadSessionGuard.isStale(authTimeSec: 1700000010, epochMs: changedMs), isFalse);
    expect(PadSessionGuard.isStale(authTimeSec: null, epochMs: changedMs), isFalse);
    expect(PadSessionGuard.isStale(authTimeSec: 1699999990, epochMs: null), isFalse);
  });

  test('번역 고침표: 원문 비교는 띄어쓰기 무시·뗴=떼, 빈 언어는 빼고 읽음', () {
    expect(TranslationOverrides.keyOf(' 바닐라 라뗴 '), '바닐라라떼');
    final m = TranslationOverrides.parse({
      'items': [
        {'src': '왕메리카노', 'ja': 'ジャンボ', 'en': ''},
        {'src': '빈 고침', 'en': ' '},
        'x',
      ],
    });
    expect(m.keys, ['왕메리카노']);
    expect(m['왕메리카노'], {'src': '왕메리카노', 'ja': 'ジャンボ'});
  });
}
