import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/models/home_extra.dart';
import 'package:boardpad/models/home_layout.dart';
import 'package:boardpad/models/order_flow.dart';

void main() {
  test('134차 랜덤 게임: 인원 맞추기 — min·max, players 글, 6+', () {
    expect(gameFitsPlayers({'minPlayers': 2, 'maxPlayers': 4}, 3), isTrue);
    expect(gameFitsPlayers({'minPlayers': 2, 'maxPlayers': 4}, 5), isFalse);
    expect(gameFitsPlayers({'players': '3~6인'}, 2), isFalse);
    expect(gameFitsPlayers({'players': '3~6인'}, 6), isTrue);
    expect(gameFitsPlayers({'players': '2인'}, 2), isTrue);
    expect(gameFitsPlayers({'players': ''}, 2), isFalse); // 인원 모름
    expect(gameFitsPlayers({'minPlayers': 3, 'maxPlayers': 8}, 6, orMore: true), isTrue);
    expect(gameFitsPlayers({'minPlayers': 2, 'maxPlayers': 5}, 6, orMore: true), isFalse);

    final games = <Map<String, dynamic>>[
      {'title': 'A', 'minPlayers': 2, 'maxPlayers': 4},
      {'title': 'B', 'minPlayers': 2, 'maxPlayers': 4, 'expansion': true},
      {'title': 'C', 'minPlayers': 4, 'maxPlayers': 10},
    ];
    expect(randomGameCandidates(games, null).map((g) => g['title']), ['A', 'C']);
    expect(randomGameCandidates(games, 2).map((g) => g['title']), ['A']);
    expect(randomGameCandidates(games, 6).map((g) => g['title']), ['C']);
  });

  test('134차 새로 들어온 게임: 30일 이내·끈 것 빼고 최근 것부터', () {
    final now = DateTime.now();
    Timestamp ago(int days) => Timestamp.fromDate(now.subtract(Duration(days: days)));
    final games = <Map<String, dynamic>>[
      {'title': 'old', 'timestamp': ago(40)},
      {'title': 'mid', 'timestamp': ago(10)},
      {'title': 'new', 'timestamp': ago(1)},
      {'title': 'hidden', 'timestamp': ago(2), 'newHidden': true},
      {'title': 'none'},
    ];
    expect(newGamesOf(games).map((g) => g['title']), ['new', 'mid']);
    expect(newGamesOf(games, limit: 1).map((g) => g['title']), ['new']);
  });

  test('134차 영업시간: 시각 읽기·자정 넘김·휴무일·24시간', () {
    expect(StoreHours.parseTime('9:30'), 570);
    expect(StoreHours.parseTime('24:00'), 1440);
    expect(StoreHours.parseTime('24:30'), isNull);
    expect(StoreHours.parseTime('12시'), isNull);
    expect(StoreHours.timeText(570), '09:30');

    // 2026-11-16 = 월요일
    DateTime at(int day, int h, int m) => DateTime(2026, 11, day, h, m);
    final day = StoreHours.fromOptions({'open': '12:00', 'close': '24:00', 'closedDays': [1]});
    expect(day.rangeText, '12:00 – 24:00');
    expect(day.isOpenAt(at(17, 13, 0)), isTrue); // 화 13시
    expect(day.isOpenAt(at(17, 11, 59)), isFalse);
    expect(day.isOpenAt(at(16, 13, 0)), isFalse); // 월 휴무

    final night = StoreHours.fromOptions({'open': '18:00', 'close': '02:00', 'closedDays': [1]});
    expect(night.isOpenAt(at(17, 1, 0)), isFalse); // 화 새벽 = 월요일 영업(휴무)
    expect(night.isOpenAt(at(16, 1, 0)), isTrue); // 월 새벽 = 일요일 영업
    expect(night.isOpenAt(at(17, 19, 0)), isTrue);
    expect(night.isOpenAt(at(17, 3, 0)), isFalse);

    final allDay = StoreHours.fromOptions({'open': '00:00', 'close': '00:00'});
    expect(allDay.isOpenAt(at(18, 4, 0)), isTrue);
    expect(StoreHours.fromOptions({}).isOpenAt(at(18, 4, 0)), isNull);
    expect(StoreHours.fromOptions({'closedDays': [7, 1, 1, 9]}).closedDays, [1, 7]);
  });

  test('134차 내 음식 상태 단계', () {
    expect(foodOrderStep('pending', OrderFlow.serve).index, 0);
    expect(foodOrderStep('preparing', OrderFlow.serve).steps.last, '자리로 전달');
    final pickup = foodOrderStep('ready', OrderFlow.pickup);
    expect(pickup.index, 2);
    expect(pickup.steps.last, '준비 완료');
  });

  test('134차 새 위젯이 홈 꾸미기 목록에 있음', () {
    for (final t in ['foodStatus', 'orderSummary', 'language', 'fingerTools', 'randomGame', 'newGames', 'storeHours']) {
      expect(specOf(t), isNotNull, reason: t);
    }
  });

  test('134차 숫자 섞인 문구 번역', () async {
    SharedPreferences.setMockInitialValues({});
    await GuestLanguage.instance.select('en');
    expect(GuestLanguage.instance.translate('외 2개'), '+2 more');
    expect(GuestLanguage.instance.translate('주문 3건'), '3 orders');
    expect(GuestLanguage.instance.translate('새로 들어온 게임'), 'New arrivals');
    await GuestLanguage.instance.select('ja');
    expect(GuestLanguage.instance.translate('주문 3건'), '注文3件');
    await GuestLanguage.instance.select('ko');
  });
}
