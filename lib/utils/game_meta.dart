import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 게임 데이터 공통 규칙 (관리자 게임 관리 화면과 손님 게임 목록이 같이 씀)

/// 난이도 단계와 색 — 월정액권 앱과 같은 기준(BGG weight 구간, 매장 난이도 스티커 색)
class DifficultyLevel {
  final String label;
  final Color color;
  final double maxWeight; // 이 값 "미만"이면 이 단계
  const DifficultyLevel(this.label, this.color, this.maxWeight);
}

const List<DifficultyLevel> difficultyLevels = [
  DifficultyLevel('매우쉬움', Color(0xFF00A1E9), 1.3),
  DifficultyLevel('쉬움', Color(0xFF23AC3A), 1.6),
  DifficultyLevel('보통', Color(0xFFF29700), 2.1),
  DifficultyLevel('어려움', Color(0xFFEA5417), 2.6),
  DifficultyLevel('매우어려움', Color(0xFFD80051), 3.1),
  DifficultyLevel('전문', Color(0xFF231917), double.infinity),
];

List<String> get difficultyLabels => difficultyLevels.map((d) => d.label).toList();

/// weight(0~5) -> 난이도 이름. weight가 없으면 null.
String? difficultyFromWeight(num? weight) {
  if (weight == null || weight <= 0) return null;
  for (final d in difficultyLevels) {
    if (weight < d.maxWeight) return d.label;
  }
  return difficultyLevels.last.label;
}

Color difficultyColor(String? label) {
  for (final d in difficultyLevels) {
    if (d.label == label) return d.color;
  }
  return Colors.grey;
}

/// 인원 표시 문자열. 손님 앱의 인원 필터가 이 문자열에서 숫자를 읽어요. (예: "2~4인", "2인")
String playersText(int? min, int? max) {
  if (min == null && max == null) return '';
  if (min == null || max == null || min == max) return '${min ?? max}인';
  return '$min~$max인';
}

/// 게임의 장르 목록. 예전 데이터('genre' 하나)도 읽어요.
List<String> gameGenres(Map<String, dynamic> data) {
  final list = data['genres'];
  if (list is List && list.isNotEmpty) return list.map((e) => e.toString()).toList();
  final g = (data['genre'] ?? '').toString();
  return g.isEmpty ? [] : [g];
}

const int newBadgeDays = 30;

/// NEW 배지: 등록 후 30일 이내이고 매장에서 끄지 않은 게임
bool isNewGame(Map<String, dynamic> data) {
  if (data['newHidden'] == true) return false;
  final ts = data['timestamp'];
  if (ts is! Timestamp) return false;
  return DateTime.now().difference(ts.toDate()).inDays < newBadgeDays;
}

/// NEW 배지를 켜고 끌 수 있는 게임인지 (등록 후 30일 이내)
bool isNewEligible(Map<String, dynamic> data) {
  final ts = data['timestamp'];
  if (ts is! Timestamp) return false;
  return DateTime.now().difference(ts.toDate()).inDays < newBadgeDays;
}

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

/// 예전 필드(genre / players / difficulty)를 새 필드에서 만들어 줌.
/// 손님 앱이 예전 필드로 필터·표시하기 때문에 저장할 때 항상 같이 넣습니다.
Map<String, dynamic> legacyGameFields({
  required List<String> genres,
  int? minPlayers,
  int? maxPlayers,
  String? difficulty,
}) {
  return {
    'genres': genres,
    'genre': genres.isNotEmpty ? genres.first : '',
    'players': playersText(minPlayers, maxPlayers),
    'difficulty': difficulty ?? '',
  };
}

/// BGG 플레이 시간(분) → 소요시간 글자. 최소·최대가 같으면 "30분", 다르면 "30~60분".
/// 최소·최대가 없으면 대표 시간(playing)으로, 그것도 없으면 null.
/// 손님 앱 소요시간 필터가 이 글자에서 '분' 앞 숫자(범위면 큰 쪽)를 읽어요.
String? playTimeTextOf(int? min, int? max, [int? playing]) {
  int? a = (min != null && min > 0) ? min : null;
  int? b = (max != null && max > 0) ? max : null;
  if (a == null && b == null) {
    return (playing != null && playing > 0) ? '$playing분' : null;
  }
  final lo = a ?? b!;
  final hi = b ?? a!;
  final x = lo < hi ? lo : hi;
  final y = lo < hi ? hi : lo;
  return x == y ? '$x분' : '$x~$y분';
}
