import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/models/party_session.dart';

void main() {
  group('인원별 추천', () {
    test('최소와 최대 인원을 모두 확인한다', () {
      expect(supportsPlayerCount('2~4명', 2), isTrue);
      expect(supportsPlayerCount('2~4명', 4), isTrue);
      expect(supportsPlayerCount('2~4명', 5), isFalse);
      expect(supportsPlayerCount('5–8명', 4), isFalse);
      expect(supportsPlayerCount('5–8명', 7), isTrue);
      expect(supportsPlayerCount('2인전용', 2), isTrue);
      expect(supportsPlayerCount('2인전용', 3), isFalse);
      expect(supportsPlayerCount('4명', 3), isFalse);
      expect(supportsPlayerCount('4명', 4), isTrue);
    });
    test('상한 없는 표기 및 잘못된 데이터', () {
      expect(supportsPlayerCount('5인 이상', 10), isTrue);
      expect(supportsPlayerCount('5인 이상', 4), isFalse);
      expect(supportsPlayerCount('6+', 9), isTrue);
      expect(supportsPlayerCount('4인 이하', 3), isTrue);
      expect(supportsPlayerCount('', 4), isFalse);
      expect(supportsPlayerCount('인원 미정', 4), isFalse);
      expect(supportsPlayerCount('8~2명', 4), isFalse);
      expect(supportsPlayerCount('0~4명', 4), isFalse);
      expect(supportsPlayerCount('2~4명', 0), isFalse);
    });
  });

  GameRound round(String game, List<String> winners, List<String> losers) =>
      GameRound(
        game: game,
        playedAt: DateTime(2026, 10, 8),
        winners: winners,
        losers: losers,
      );

  group('승패와 음료 내기', () {
    test('게임별 집계, 미참가 제외, 전체 게임의 최다 패배자', () {
      final session = PartySession(
        players: ['도리', '민수', '지수'],
        cafe: '보드카페',
        drink: '아메리카노',
        rounds: [
          round('게임 A', ['도리'], ['민수']),
          round('게임 B', ['도리', '지수'], ['민수']),
          round('게임 B', ['민수'], ['지수']),
        ],
      );
      expect(session.wins(), {'도리': 2, '민수': 1, '지수': 1});
      expect(session.losses(), {'도리': 0, '민수': 2, '지수': 1});
      expect(session.losses(game: '게임 A'), {'도리': 0, '민수': 1, '지수': 0});
      expect(session.drinkWinners, ['민수']);
    });
    test('동률은 공동 당첨, 기록 없으면 당첨자 없음', () {
      final empty = PartySession(players: ['도리', '민수', '지수']);
      expect(empty.drinkWinners, isEmpty);
      final tied = empty.withRounds([
        round('게임', ['도리'], ['민수', '지수']),
      ]);
      expect(tied.drinkWinners, ['민수', '지수']);
      expect(tied.withRounds([]).losses().values, everyElement(0));
      expect(tied.withRounds([]).drinkWinners, isEmpty);
    });
    test('JSON 복원 후에도 기록과 집계가 유지된다', () {
      final original = PartySession(
        players: ['도리', '민수'],
        cafe: '카페',
        drink: '음료 한 잔씩',
        rounds: [
          round('게임', ['도리'], ['민수']),
        ],
      );
      final restored = PartySession.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
      expect(restored.drinkWinners, ['민수']);
    });
    test('중복 이름, 승패 중복, 없는 참가자를 거부한다', () {
      expect(() => PartySession(players: ['도리', '도리']), throwsArgumentError);
      expect(() => round('게임', ['도리'], ['도리']), throwsArgumentError);
      expect(() => round('게임', ['도리'], []), throwsArgumentError);
      expect(
        () => PartySession(
          players: ['도리'],
          rounds: [
            round('게임', ['도리'], ['민수']),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('밸런스 게임과 팀', () {
    test('한 바퀴 동안 질문 중복 없음, 다음 바퀴 첫 질문도 연속 중복 없음', () {
      final deck = BalanceDeck(random: Random(42));
      final questions = List.generate(
        balanceQuestions.length,
        (_) => deck.next(),
      );
      expect(questions.toSet().length, balanceQuestions.length);
      expect(deck.next(), isNot(same(questions.last)));
    });
    test('선택에 따라 팀을 만들며 모든 인원이 선택해야 한다', () {
      final players = ['도리', '민수', '지수'];
      expect(choiceTeams(players, {'도리': true, '민수': false, '지수': true}), [
        ['도리', '지수'],
        ['민수'],
      ]);
      expect(choiceTeams(players, {for (final p in players) p: true}), [
        players,
        <String>[],
      ]);
      expect(() => choiceTeams(players, {'도리': true}), throwsArgumentError);
    });
    test('균등 팀에는 누락·중복이 없고 인원 차이가 최대 1명', () {
      for (var count = 2; count <= 30; count++) {
        final players = List.generate(count, (i) => '참가자 $i');
        final teams = balancedRandomTeams(players, Random(count));
        final assigned = teams.expand((team) => team).toList();
        expect(assigned, unorderedEquals(players));
        expect(assigned.toSet().length, count);
        expect((teams[0].length - teams[1].length).abs(), lessThanOrEqualTo(1));
      }
    });
  });
}
