import 'dart:math';

/// Accepts the existing catalog's players field, e.g. 2~4명 / 2인전용 / 5인 이상.
bool supportsPlayerCount(String players, int count) {
  if (count < 1) return false;
  final values = RegExp(r'\d+')
      .allMatches(players)
      .map((m) => int.parse(m.group(0)!))
      .toList();
  if (values.isEmpty || values.length > 2 || values.any((n) => n < 1)) {
    return false;
  }
  if (values.length == 1) {
    if (players.contains('이상') || players.contains('+')) {
      return count >= values.first;
    }
    if (players.contains('이하')) return count <= values.first;
    return count == values.first;
  }
  return values.first <= values.last &&
      count >= values.first &&
      count <= values.last;
}

class GameRound {
  final String game;
  final DateTime playedAt;
  final List<String> winners;
  final List<String> losers;

  GameRound({
    required this.game,
    required this.playedAt,
    required List<String> winners,
    required List<String> losers,
  }) : winners = List.unmodifiable(winners),
       losers = List.unmodifiable(losers) {
    if (game.trim().isEmpty ||
        winners.isEmpty ||
        losers.isEmpty ||
        winners.toSet().length != winners.length ||
        losers.toSet().length != losers.length ||
        winners.any(losers.contains)) {
      throw ArgumentError('게임과 서로 다른 승자·패자를 선택하세요.');
    }
  }

  Map<String, dynamic> toJson() => {
    'game': game,
    'playedAt': playedAt.toIso8601String(),
    'winners': winners,
    'losers': losers,
  };

  factory GameRound.fromJson(Map<String, dynamic> json) => GameRound(
    game: json['game'] as String,
    playedAt: DateTime.parse(json['playedAt'] as String),
    winners: List<String>.from(json['winners'] as List),
    losers: List<String>.from(json['losers'] as List),
  );
}

class PartySession {
  final List<String> players;
  final String cafe;
  final String drink;
  final String? menuId;
  final List<GameRound> rounds;

  PartySession({
    List<String> players = const [],
    this.cafe = '',
    this.drink = '',
    this.menuId,
    List<GameRound> rounds = const [],
  }) : players = List.unmodifiable(players),
       rounds = List.unmodifiable(rounds) {
    if (players.any((p) => p.trim().isEmpty) ||
        players.toSet().length != players.length ||
        rounds.any(
          (r) => [...r.winners, ...r.losers].any((p) => !players.contains(p)),
        )) {
      throw ArgumentError('참가자 목록이 올바르지 않습니다.');
    }
  }

  PartySession withRounds(List<GameRound> value) => PartySession(
    players: players,
    cafe: cafe,
    drink: drink,
    menuId: menuId,
    rounds: value,
  );

  Map<String, int> wins({String? game}) => _counts(true, game);
  Map<String, int> losses({String? game}) => _counts(false, game);

  Map<String, int> _counts(bool win, String? game) {
    final result = {for (final p in players) p: 0};
    for (final round in rounds.where((r) => game == null || r.game == game)) {
      for (final p in win ? round.winners : round.losers) {
        result[p] = result[p]! + 1;
      }
    }
    return result;
  }

  List<String> get drinkWinners {
    final counts = losses();
    final maxLosses = counts.values.fold<int>(0, max);
    if (maxLosses == 0) return [];
    return players.where((p) => counts[p] == maxLosses).toList();
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'players': players,
    'cafe': cafe,
    'drink': drink,
    'menuId': menuId,
    'rounds': rounds.map((r) => r.toJson()).toList(),
  };

  factory PartySession.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('지원하지 않는 기록입니다.');
    return PartySession(
      players: List<String>.from(json['players'] as List),
      cafe: json['cafe'] as String,
      drink: json['drink'] as String,
      menuId: json['menuId'] as String?,
      rounds: (json['rounds'] as List)
          .map((r) => GameRound.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList(),
    );
  }
}

class BalanceQuestion {
  final String a;
  final String b;
  const BalanceQuestion(this.a, this.b);
}

const balanceQuestions = <BalanceQuestion>[
  BalanceQuestion('평생 여름만 살기', '평생 겨울만 살기'),
  BalanceQuestion('순간 이동 능력', '시간을 멈추는 능력'),
  BalanceQuestion('계획대로 여행하기', '즉흥적으로 여행하기'),
  BalanceQuestion('바다에서 휴가', '산에서 휴가'),
  BalanceQuestion('매일 새로운 음식 먹기', '매일 최애 음식 먹기'),
  BalanceQuestion('영화관에서 영화 보기', '집에서 편하게 영화 보기'),
  BalanceQuestion('아침형 인간 되기', '밤에 집중 잘 되는 사람 되기'),
  BalanceQuestion('보드게임 규칙 바로 이해하기', '주사위 운이 항상 좋기'),
  BalanceQuestion('치열한 전략 게임', '다 같이 웃는 파티 게임'),
  BalanceQuestion('한 게임 깊게 즐기기', '여러 게임 짧게 즐기기'),
  BalanceQuestion('맛있는 디저트', '맛있는 음료'),
  BalanceQuestion('강아지와 대화하기', '고양이와 대화하기'),
  BalanceQuestion('혼자 떠나는 여행', '친구들과 떠나는 여행'),
  BalanceQuestion('사진으로 추억 남기기', '일기로 추억 남기기'),
  BalanceQuestion('요리 실력 최고 되기', '악기 연주 최고 되기'),
  BalanceQuestion('책으로 이야기 즐기기', '게임으로 이야기 즐기기'),
  BalanceQuestion('과거의 나에게 조언하기', '미래의 나에게 질문하기'),
  BalanceQuestion('놀이공원 가기', '전시회 가기'),
  BalanceQuestion('한 번에 크게 이기기', '조금씩 꾸준히 이기기'),
  BalanceQuestion('항상 선공하기', '항상 후공하기'),
  BalanceQuestion('협력해서 목표 달성하기', '각자 경쟁해서 우승하기'),
  BalanceQuestion('비 오는 날 카페', '맑은 날 공원'),
  BalanceQuestion('모든 언어 이해하기', '모든 악기 연주하기'),
  BalanceQuestion('미래 도시 여행', '옛 도시 여행'),
  BalanceQuestion('달콤한 간식', '짭짤한 간식'),
  BalanceQuestion('한 달 인터넷 없이 살기', '한 달 배달 음식 없이 살기'),
  BalanceQuestion('노래 잘 부르기', '춤 잘 추기'),
  BalanceQuestion('하늘을 날기', '바닷속에서 숨쉬기'),
  BalanceQuestion('작은 모임 자주 만나기', '큰 모임 가끔 만나기'),
  BalanceQuestion('게임에서 멋지게 역전하기', '처음부터 끝까지 앞서기'),
];

/// Every question appears once per deck; no immediate repeat across decks.
class BalanceDeck {
  final Random random;
  final List<BalanceQuestion> _remaining = [];
  BalanceQuestion? _last;
  BalanceDeck({Random? random}) : random = random ?? Random();

  BalanceQuestion next() {
    if (_remaining.isEmpty) {
      _remaining.addAll(balanceQuestions);
      _remaining.shuffle(random);
      if (identical(_remaining.last, _last)) {
        final first = _remaining.removeAt(0);
        _remaining.add(first);
      }
    }
    return _last = _remaining.removeLast();
  }
}

List<List<String>> choiceTeams(List<String> players, Map<String, bool> votes) {
  if (players.length < 2 || players.any((p) => !votes.containsKey(p))) {
    throw ArgumentError('모두 A 또는 B를 선택하세요.');
  }
  return [
    players.where((p) => votes[p] == true).toList(),
    players.where((p) => votes[p] == false).toList(),
  ];
}

List<List<String>> balancedRandomTeams(List<String> players, Random random) {
  final shuffled = [...players]..shuffle(random);
  return [
    for (var team = 0; team < 2; team++)
      [for (var i = team; i < shuffled.length; i += 2) shuffled[i]],
  ];
}
