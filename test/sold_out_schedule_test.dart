import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/services/sold_out_schedule.dart';

// 112차: 특정 시간 자동 품절 — 시간 계산·붙는 곳·저장 모양
void main() {
  // 2026-11-16 = 월요일
  DateTime at(int day, int h, int m) => DateTime(2026, 11, day, h, m);

  test('같은 날 안 (14:00 ~ 17:00)', () {
    final r = SoldOutRule.fromJson({'id': 'a', 'from': '14:00', 'to': '17:00', 'categories': ['음식']})!;
    expect(r.activeAt(at(16, 13, 59)), isFalse);
    expect(r.activeAt(at(16, 14, 0)), isTrue);
    expect(r.activeAt(at(16, 16, 59)), isTrue);
    expect(r.activeAt(at(16, 17, 0)), isFalse);
    expect(r.timeLabel, '14:00 ~ 17:00');
  });

  test('밤을 넘김 (22:00 ~ 다음 날 11:00) + 요일은 시작한 날 기준', () {
    final r = SoldOutRule.fromJson({'id': 'b', 'from': '22:00', 'to': '11:00', 'days': [5], 'menuIds': ['m1']})!; // 금요일만
    expect(r.activeAt(at(20, 22, 30)), isTrue); // 금 22:30
    expect(r.activeAt(at(21, 10, 59)), isTrue); // 토 10:59 (금요일에 시작)
    expect(r.activeAt(at(21, 11, 0)), isFalse);
    expect(r.activeAt(at(21, 23, 0)), isFalse); // 토 밤은 아님
    expect(r.activeAt(at(20, 9, 0)), isFalse); // 금 오전은 목요일 몫 → 아님
    expect(r.timeLabel, '22:00 ~ 다음 날 11:00');
    expect(r.daysLabel, '금');
  });

  test('월요일 새벽은 일요일 밤 규칙', () {
    final r = SoldOutRule.fromJson({'id': 'c', 'from': '23:00', 'to': '02:00', 'days': [7], 'categories': ['x']})!;
    expect(r.activeAt(at(16, 1, 0)), isTrue); // 월 01:00
    expect(r.activeAt(at(17, 1, 0)), isFalse); // 화 01:00
  });

  test('시작 = 끝이면 하루 종일, 꺼진 규칙은 안 걸림', () {
    final r = SoldOutRule.fromJson({'id': 'd', 'from': '00:00', 'to': '00:00', 'days': [6, 7], 'categories': ['x']})!;
    expect(r.activeAt(at(21, 15, 0)), isTrue); // 토
    expect(r.activeAt(at(20, 15, 0)), isFalse); // 금
    expect(r.daysLabel, '주말');
    expect(r.copyWith(enabled: false).activeAt(at(21, 15, 0)), isFalse);
  });

  test('붙는 곳 = 카테고리 + 메뉴, 손으로 켠 품절과 합침', () {
    final rules = [
      SoldOutRule.fromJson({'id': 'e', 'from': '22:00', 'to': '11:00', 'categories': ['음식/튀김'], 'menuIds': ['ramen']})!,
    ];
    final night = at(18, 23, 0);
    final noon = at(18, 12, 0);
    expect(SoldOutSchedule.menuSoldOut({'category': '음식/튀김'}, 'fries', rules, night), isTrue);
    expect(SoldOutSchedule.menuSoldOut({'category': '라면'}, 'ramen', rules, night), isTrue);
    expect(SoldOutSchedule.menuSoldOut({'category': '음료'}, 'cola', rules, night), isFalse);
    expect(SoldOutSchedule.menuSoldOut({'category': '음식/튀김'}, 'fries', rules, noon), isFalse);
    expect(SoldOutSchedule.menuSoldOut({'category': '음료', 'isSoldOut': true}, 'cola', rules, noon), isTrue);
    expect(SoldOutSchedule.menuSoldOut({'category': '음료'}, 'cola', const [], noon), isFalse);
  });

  test('저장 왕복 — 요일 7개는 매일(빈 목록), 이상한 값은 버림', () {
    final r = SoldOutRule.fromJson({
      'id': 'f',
      'name': '주방 마감',
      'from': '9:05',
      'to': '25:00', // 잘못된 값 → 기본 11:00
      'days': [1, 2, 3, 4, 5, 6, 7],
      'categories': ['a', ''],
    })!;
    expect(r.from, 9 * 60 + 5);
    expect(r.to, 11 * 60);
    expect(r.days, isEmpty);
    expect(r.categories, ['a']);
    final back = SoldOutRule.fromJson(r.toJson())!;
    expect(back.toJson(), r.toJson());
    expect(back.toJson()['from'], '09:05');
    expect(SoldOutRule.fromJson({'name': 'id 없음'}), isNull);
  });
}
