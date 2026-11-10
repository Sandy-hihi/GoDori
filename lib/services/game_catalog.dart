import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store_scope.dart';
import 'usage_meter.dart';

/// 손님 패드 게임 목록 (92차) — Firestore 읽기 비용 줄이기
///
/// 예전: 게임 목록·인원별 추천 화면을 열 때마다 게임 약 650개를 전부 Firestore에서 읽음(매장당 하루 13만 번 읽기).
/// 지금: 하루 1번만 읽어서 패드에 저장(SharedPreferences — 앱을 껐다 켜도 남음)하고, 그날은 저장한 것을 씀.
///   다시 읽는 때: ① 날짜가 바뀐 뒤 처음 열 때
///               ② 사장님이 관리자 웹 '보드게임 관리'의 '손님 앱 새로고침'을 누를 때
///                  (settings/appRefresh.gamesUpdatedAt이 바뀜 → 패드가 문서 1개만 지켜보다가 알아챔)
///   게임을 추가·수정·삭제·숨김해도 ②를 누르기 전(또는 다음 날)까지는 패드에 안 보임.
/// 공용 룰 영상(92차, shared/ruleVideos)도 같이 1번 읽어서, 매장 영상이 없는 게임에 붙임(ruleVideo + ruleVideoShared).
///
/// 사용: `await GameCatalog.load()` → 게임 목록(각 항목에 '_docId'), 바뀌면 `GameCatalog.revision`이 올라감.
class GameCatalog {
  GameCatalog._();

  static const _prefsPrefix = 'gameCatalog.v1.';

  /// 패드에 있는 목록이 낡았을 때 올라감 → 열려 있는 화면은 load()를 다시 부름
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static String? _store; // 지금 들고 있는 목록의 매장
  static List<Map<String, dynamic>>? _games;
  static String? _day; // 받은 날짜 (패드 시계 기준)
  static int _version = 0; // 받을 때의 gamesUpdatedAt(밀리초)
  static Future<List<Map<String, dynamic>>>? _loading;

  static String? _watchStore;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static int? _remoteVersion; // 서버의 gamesUpdatedAt (아직 모르면 null)
  static Completer<void>? _versionReady;

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static bool get _fresh => _games != null && _day == _today() && (_remoteVersion == null || _remoteVersion == _version);

  /// 게임 목록 (이용 가능한 것만). 그날 받은 게 있으면 Firestore를 읽지 않음.
  static Future<List<Map<String, dynamic>>> load() async {
    if (!StoreScope.isSet) return const [];
    final store = StoreScope.id;
    if (_store != store) {
      _store = store;
      _games = null;
      _day = null;
      _version = 0;
    }
    _watch(store);
    if (_fresh) return _games!;
    if (_games == null) {
      await _restore(store);
      if (_fresh) return _games!;
    }
    return _loading ??= _fetch(store).whenComplete(() => _loading = null);
  }

  /// 다음 load()에서 꼭 새로 받게 (지금 들고 있는 목록은 버림)
  static void invalidate() {
    _games = null;
    _day = null;
    revision.value++;
  }

  // ── 서버의 '손님 앱 새로고침' 표시 지켜보기 (문서 1개) ──
  static void _watch(String store) {
    if (_watchStore == store && _sub != null) return;
    _sub?.cancel();
    _watchStore = store;
    _remoteVersion = null;
    _versionReady = Completer<void>();
    _sub = StoreScope.col('settings').doc('appRefresh').snapshots().listen((doc) {
      final ts = doc.data()?['gamesUpdatedAt'];
      _onVersion(ts is Timestamp ? ts.millisecondsSinceEpoch : 0);
    }, onError: (Object e) {
      debugPrint('게임 목록 새로고침 표시를 못 읽음: $e');
      _sub = null; // 다음 load() 때 다시 지켜봄
      _watchStore = null;
      final c = _versionReady;
      if (c != null && !c.isCompleted) c.complete();
    }, cancelOnError: true);
  }

  static void _onVersion(int v) {
    _remoteVersion = v;
    final c = _versionReady;
    if (c != null && !c.isCompleted) c.complete();
    if (_games != null && v != _version) {
      // 사장님이 새로고침을 눌렀음(또는 패드가 꺼져 있던 사이에 눌렀음) → 다시 받기
      _games = null;
      _day = null;
      revision.value++;
    }
  }

  static Future<int> _currentVersion() async {
    final c = _versionReady;
    if (_remoteVersion == null && c != null && !c.isCompleted) {
      try {
        await c.future.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    return _remoteVersion ?? 0;
  }

  // ── Firestore에서 받기 ──
  static Future<List<Map<String, dynamic>>> _fetch(String store) async {
    final version = await _currentVersion();
    final snap = await StoreScope.col('games').where('isAvailable', isEqualTo: true).get().metered();
    final games = [for (final d in snap.docs) <String, dynamic>{...d.data(), '_docId': d.id}];
    Map<dynamic, dynamic> shared = const {};
    try {
      final s = await FirebaseFirestore.instance.collection('shared').doc('ruleVideos').get();
      if (!s.metadata.isFromCache) UsageMeter.addReads(1);
      final v = s.data()?['videos'];
      if (v is Map) shared = v;
    } catch (e) {
      debugPrint('공용 룰 영상 목록을 못 읽음(없어도 됨): $e');
    }
    _mergeShared(games, shared);
    if (!StoreScope.isSet || StoreScope.id != store) return games; // 받는 사이 다른 매장으로 바뀜
    _games = games;
    _day = _today();
    _version = version;
    unawaited(_save(store));
    return games;
  }

  /// 매장 영상이 없는 게임에 같은 BGG 번호(geekId)의 공용 영상을 붙임
  static void _mergeShared(List<Map<String, dynamic>> games, Map<dynamic, dynamic> shared) {
    if (shared.isEmpty) return;
    for (final g in games) {
      final own = g['ruleVideo'];
      final hasOwn = own is Map && own.values.any((v) => v is Map && (v['key'] ?? '').toString().isNotEmpty);
      if (hasOwn) continue;
      if ((g['ruleVideoUrl'] ?? '').toString().startsWith('http')) continue; // 예전 방식 매장 영상도 매장 것이 먼저
      final id = (g['geekId'] ?? '').toString().trim();
      final e = id.isEmpty ? null : shared[id];
      if (e is! Map) continue;
      final rv = <String, dynamic>{
        for (final q in const ['q1080', 'q720'])
          if (e[q] is Map) q: Map<String, dynamic>.from(e[q] as Map),
      };
      if (rv.isEmpty) continue;
      g['ruleVideo'] = rv;
      g['ruleVideoShared'] = true;
    }
  }

  // ── 패드에 저장 (앱을 다시 켜도 그날은 다시 안 읽게) ──
  static Future<void> _save(String store) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '$_prefsPrefix$store', jsonEncode({'day': _day, 'version': _version, 'games': _enc(_games)}));
    } catch (e) {
      debugPrint('게임 목록 저장 실패(다음에 다시 받음): $e');
    }
  }

  static Future<void> _restore(String store) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$store');
      if (raw == null) return;
      final m = jsonDecode(raw);
      if (m is! Map || m['day'] != _today() || m['games'] is! List) return;
      if (_store != store) return;
      _games = [for (final g in (_dec(m['games']) as List)) if (g is Map<String, dynamic>) g];
      _day = m['day'] as String;
      _version = (m['version'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('저장된 게임 목록을 못 읽음: $e');
    }
  }

  // Timestamp(등록일 — NEW 표시에 씀)는 JSON에 못 넣어서 {'__ts': 밀리초}로 바꿔 저장
  static Object? _enc(Object? v) {
    if (v is Timestamp) return {'__ts': v.millisecondsSinceEpoch};
    if (v is DateTime) return {'__ts': v.millisecondsSinceEpoch};
    if (v is Map) return {for (final e in v.entries) e.key.toString(): _enc(e.value)};
    if (v is List) return [for (final x in v) _enc(x)];
    if (v == null || v is num || v is String || v is bool) return v;
    return v.toString();
  }

  static Object? _dec(Object? v) {
    if (v is Map) {
      if (v.length == 1 && v['__ts'] is num) return Timestamp.fromMillisecondsSinceEpoch((v['__ts'] as num).toInt());
      return <String, dynamic>{for (final e in v.entries) e.key.toString(): _dec(e.value)};
    }
    if (v is List) return [for (final x in v) _dec(x)];
    return v;
  }
}
