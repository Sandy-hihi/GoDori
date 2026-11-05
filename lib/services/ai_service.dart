import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/usage_meter.dart';

/// AI 게임 추천
/// - 오늘의 추천: 서버 함수(dailyPicks)가 매일 settings/aiPicks 문서에 써 둔 것을 읽기만 함
/// - 맞춤 추천: 서버 함수(/api/ai/recommend)를 부름. 서버가 없거나 실패하면 앱 안의 규칙으로 대신 고름
/// (서버 코드: functions/src/ai.js)

class AiPick {
  final String gameId;
  final String title;
  final String reason;
  final String? imageUrl;
  final String? players;
  final String? time;
  final String? difficulty;
  final String? videoUrl;

  const AiPick({
    required this.gameId,
    required this.title,
    required this.reason,
    this.imageUrl,
    this.players,
    this.time,
    this.difficulty,
    this.videoUrl,
  });

  factory AiPick.fromJson(Map<String, dynamic> j) => AiPick(
        gameId: (j['gameId'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        reason: (j['reason'] ?? '').toString(),
        imageUrl: _str(j['imageUrl']),
        players: _str(j['players']),
        time: _str(j['time']),
        difficulty: _str(j['difficulty']),
        videoUrl: _str(j['videoUrl']),
      );

  factory AiPick.fromGame(String id, Map<String, dynamic> g, String reason) => AiPick(
        gameId: id,
        title: (g['title'] ?? '').toString(),
        reason: reason,
        imageUrl: _str(g['imageUrl']),
        players: _str(g['players']),
        time: _str(g['time']),
        difficulty: _str(g['difficulty']),
        videoUrl: _str(g['videoUrl']),
      );
}

String? _str(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// 손님이 고른 조건
class AiAsk {
  final int players; // 6 = 6명 이상
  final String experience; // first | sometimes | often
  final Set<String> moods; // brain | party | coop | bluff | quick
  final String time; // 30 | 60 | any

  const AiAsk({required this.players, required this.experience, required this.moods, required this.time});

  Map<String, dynamic> toJson() => {
        'players': players,
        'experience': experience,
        'moods': moods.toList(),
        'time': time,
      };

  List<String> get labels => [
        players >= 6 ? '6명 이상' : '$players명',
        aiExperienceLabels[experience] ?? '',
        ...moods.map((m) => aiMoodLabels[m] ?? m),
        aiTimeLabels[time] ?? '',
      ];
}

const Map<String, String> aiExperienceLabels = {'first': '처음이에요', 'sometimes': '가끔 해요', 'often': '자주 해요'};
const Map<String, String> aiMoodLabels = {
  'brain': '머리싸움',
  'party': '왁자지껄 파티',
  'coop': '다 같이 협력',
  'bluff': '눈치·심리전',
  'quick': '짧게 여러 판',
};
const Map<String, String> aiTimeLabels = {'30': '30분 이내', '60': '1시간 정도', 'any': '상관없어요'};

class AiResult {
  final List<AiPick> picks;
  final bool fromAi; // false면 앱 규칙으로 고른 것
  const AiResult(this.picks, this.fromAi);
}

class AiService {
  static const String deployedOrigin = 'https://godori-pad.web.app'; // 49차: 예전 platform6-boardpad.web.app

  static String _origin() {
    final base = Uri.base;
    final isHttp = base.scheme == 'http' || base.scheme == 'https';
    final isLocal = base.host == 'localhost' || base.host == '127.0.0.1';
    if (isHttp && !isLocal) return base.origin;
    return deployedOrigin;
  }

  static String todayKey([DateTime? now]) {
    final t = now ?? DateTime.now();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  /// 오늘 날짜의 AI 추천 (없거나 날짜가 지났으면 null)
  static Stream<List<AiPick>?> todayPicks() {
    return StoreScope.col('settings').doc('aiPicks').snapshots().map((snap) {
      final d = snap.data();
      if (d == null || d['date'] != todayKey() || d['picks'] is! List) return null;
      final picks = <AiPick>[];
      for (final p in d['picks'] as List) {
        if (p is Map) picks.add(AiPick.fromJson(p.map((k, v) => MapEntry(k.toString(), v))));
      }
      return picks.isEmpty ? null : picks;
    }).handleError((_) {});
  }

  /// AI 추천이 없을 때: 직원 추천 게임 중에서 날짜마다 다르게
  static Future<List<AiPick>> staffPicks(int count, {List<String> exclude = const []}) async {
    try {
      final snap = await StoreScope.col('games')
          .where('isAvailable', isEqualTo: true)
          .where('isRecommended', isEqualTo: true)
          .get()
          .metered();
      final docs = snap.docs.where((d) => !exclude.contains(d.id)).toList();
      docs.shuffle(Random(todayKey().hashCode));
      return docs.take(count).map((d) => AiPick.fromGame(d.id, d.data(), '직원이 추천하는 게임이에요')).toList();
    } catch (_) {
      return [];
    }
  }

  /// 맞춤 추천: 서버(AI) → 실패하면 앱 규칙
  static Future<AiResult> recommend(AiAsk ask, {int count = 3, List<String> exclude = const []}) async {
    try {
      final res = await http
          .post(
            Uri.parse('${_origin()}/api/ai/recommend'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({...ask.toJson(), 'count': count, 'exclude': exclude}),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['picks'] is List) {
          final picks = (body['picks'] as List)
              .whereType<Map>()
              .map((p) => AiPick.fromJson(p.map((k, v) => MapEntry(k.toString(), v))))
              .where((p) => p.gameId.isNotEmpty && p.title.isNotEmpty)
              .toList();
          if (picks.isNotEmpty) return AiResult(picks, body['source'] == 'ai');
        }
      }
    } catch (_) {
      // 서버가 없거나 연결 실패 → 아래 규칙 추천
    }
    return AiResult(await localRecommend(ask, count: count, exclude: exclude), false);
  }

  /// 앱 안의 규칙 추천 (서버 함수의 규칙과 같은 기준)
  static Future<List<AiPick>> localRecommend(AiAsk ask, {int count = 3, List<String> exclude = const []}) async {
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await StoreScope.col('games').where('isAvailable', isEqualTo: true).get().metered();
    } catch (_) {
      return [];
    }
    final scored = <({double score, AiPick pick})>[];
    for (final doc in snap.docs) {
      if (exclude.contains(doc.id)) continue;
      final r = scoreGame(doc.data(), ask);
      if (r == null) continue;
      scored.add((score: r.score, pick: AiPick.fromGame(doc.id, doc.data(), r.reason)));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(count).map((e) => e.pick).toList();
  }

  // ── 규칙 점수 ──

  static const Map<String, List<String>> _moodKeywords = {
    'brain': ['전략', '두뇌', '추상', '퍼즐', '경제', '엔진'],
    'party': ['파티', '순발력', '액션', '단어', '그림', '웃음'],
    'coop': ['협력'],
    'bluff': ['블러핑', '심리', '추리', '마피아', '정체', '눈치'],
    'quick': [],
  };

  static ({int min, int max})? playersRange(Map<String, dynamic> g) {
    final mn = g['minPlayers'];
    final mx = g['maxPlayers'];
    if (mn is num && mx is num) return (min: mn.toInt(), max: mx.toInt());
    final text = (g['players'] ?? '').toString();
    final nums = RegExp(r'\d+').allMatches(text).map((m) => int.parse(m.group(0)!)).toList();
    if (nums.isEmpty) return null;
    if (text.contains('이상')) return (min: nums.first, max: 99);
    if (nums.length == 1) return (min: nums.first, max: nums.first);
    return (min: nums.first, max: nums.last);
  }

  static int? minutesOf(Map<String, dynamic> g) {
    final text = (g['time'] ?? '').toString();
    final hour = RegExp(r'(\d+)\s*시간').firstMatch(text);
    final nums = RegExp(r'\d+').allMatches(text.replaceAll(RegExp(r'\d+\s*시간'), '')).map((m) => int.parse(m.group(0)!)).toList();
    var total = hour != null ? int.parse(hour.group(1)!) * 60 : 0;
    if (nums.isNotEmpty) total += nums.reduce(max);
    return total == 0 ? null : total;
  }

  /// 조건에 안 맞으면 null, 맞으면 점수와 한 줄 이유
  static ({double score, String reason})? scoreGame(Map<String, dynamic> g, AiAsk ask) {
    double score = 0;
    final reasons = <String>[];

    final range = playersRange(g);
    if (range != null) {
      final p = ask.players;
      final fits = p >= 6 ? range.max >= 6 : (p >= range.min && p <= range.max);
      if (!fits) return null;
      score += 3;
      reasons.add(p >= 6 ? '여럿이 함께 하기 좋고' : '$p명이 하기 좋고');
    }

    final minutes = minutesOf(g);
    if (minutes != null) {
      if (ask.time == '30') {
        if (minutes > 45) return null;
        if (minutes <= 30) {
          score += 2;
          reasons.add('30분 안에 끝나요');
        }
      } else if (ask.time == '60') {
        if (minutes > 90) score -= 2;
        if (minutes >= 30 && minutes <= 75) {
          score += 2;
          reasons.add('1시간 안팎이면 충분해요');
        }
      }
      if (ask.moods.contains('quick') && minutes <= 20) {
        score += 2;
        reasons.add('짧게 여러 판 하기 좋아요');
      }
    }

    final diff = (g['difficulty'] ?? '').toString();
    switch (ask.experience) {
      case 'first':
        if (diff == '매우쉬움' || diff == '쉬움') {
          score += 3;
          reasons.add('처음이어도 금방 배워요');
        }
        if (diff == '어려움' || diff == '매우어려움' || diff == '전문') score -= 4;
        break;
      case 'sometimes':
        if (diff == '쉬움' || diff == '보통') score += 2;
        if (diff == '매우어려움' || diff == '전문') score -= 3;
        break;
      case 'often':
        if (diff == '보통' || diff == '어려움' || diff == '매우어려움') {
          score += 2;
          reasons.add('해 볼 만한 깊이가 있어요');
        }
        break;
    }

    final words = [
      ...((g['genres'] is List) ? (g['genres'] as List).map((e) => e.toString()) : <String>[]),
      (g['genre'] ?? '').toString(),
      (g['tags'] ?? '').toString(),
    ].join(' ');
    for (final mood in ask.moods) {
      final keys = _moodKeywords[mood] ?? const [];
      if (keys.any(words.contains)) {
        score += 2;
        reasons.add('${aiMoodLabels[mood]} 분위기에 맞아요');
      }
    }

    if (g['isRecommended'] == true) {
      score += 1;
    }

    final reason = reasons.isEmpty ? '조건에 맞는 게임이에요' : reasons.take(2).join(', ');
    return (score: score, reason: reason);
  }
}
