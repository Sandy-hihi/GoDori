import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:boardpad/screens/login_screen.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/widgets/pad_shell.dart';

/// 비밀번호를 바꾸면 패드 강제 로그아웃 (120차)
///
/// 관리자 웹 '매장 설정'에서 비밀번호를 바꾸면 서버(/api/store/passwords)가
///   stores/{매장}.authEpoch = { pad: 바꾼 시각(ms), admin: 바꾼 시각(ms) } 를 씀
///   - 패드 비밀번호를 바꾸면 pad·admin 둘 다 (손님 패드 + 관리자 패드(방 0) — 방 0도 패드 비밀번호로 들어오므로)
///   - 관리자 PIN을 바꾸면 admin만 (관리자 패드)
///   - 관리자 웹 비밀번호는 패드와 상관없어서 안 씀
/// 패드는 자기 매장 문서(stores/{매장} — 누구나 읽기)를 구독하다가, 자기 로그인 시각(토큰 auth_time)이
/// 그 시각보다 앞이면 로그아웃(자동 로그인도 끔) → 패드 로그인 화면에 안내 문구.
/// 서버는 그 패드들의 갱신 토큰도 취소함(앱이 꺼져 있던 패드도 다음에 켤 때·1시간 안에 로그인이 풀림).
/// main.dart 의 MaterialApp.builder 에서 모든 화면을 감쌈.
class PadSessionGuard extends StatefulWidget {
  final Widget child;
  const PadSessionGuard({super.key, required this.child});

  /// 로그인 화면에 보여 줄 안내 (guest_messages.dart에 번역 있음)
  static const kickedNotice = '매장 비밀번호가 바뀌어 로그아웃됐어요. 다시 로그인해 주세요.';

  /// 이 로그인이 바뀐 비밀번호보다 먼저인지 (테스트용으로 따로 뺌)
  /// authTimeSec: 토큰 auth_time(초), epochMs: stores/{매장}.authEpoch.pad 또는 admin(밀리초)
  @visibleForTesting
  static bool isStale({required num? authTimeSec, required num? epochMs}) {
    if (authTimeSec == null || epochMs == null || epochMs <= 0) return false;
    // auth_time은 초 단위(내림) — 바꾼 바로 그 초에 새로 로그인한 패드를 쫓아내지 않게 1초 여유
    return authTimeSec * 1000 + 1000 <= epochMs;
  }

  @override
  State<PadSessionGuard> createState() => _PadSessionGuardState();
}

class _PadSessionGuardState extends State<PadSessionGuard> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _storeSub;
  String? _watchKey; // '매장/admin|pad'
  num? _authTime; // 지금 로그인의 auth_time(초)
  String _kind = 'pad';
  bool _kicking = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    try {
      _authSub = FirebaseAuth.instance.idTokenChanges().listen(_onUser);
    } catch (_) {
      // Firebase 초기화 전(테스트 등) — 감시 없이
    }
  }

  Future<void> _onUser(User? user) async {
    final gen = ++_gen;
    String? store;
    String kind = 'pad';
    num? authTime;
    if (user != null) {
      try {
        final claims = await tokenClaimsOf(user); // 윈도우 앱에서도 읽히게
        final s = claims?['store'];
        if (s is String && (claims?['pad'] == true || claims?['admin'] == true)) {
          store = s;
          kind = claims?['admin'] == true ? 'admin' : 'pad';
          final at = claims?['auth_time'];
          authTime = at is num ? at : num.tryParse('${at ?? ''}');
        }
      } catch (_) {
        return; // 토큰을 잠깐 못 읽음(인터넷 끊김 등) — 지금 구독 그대로
      }
    }
    if (gen != _gen) return;
    _authTime = authTime;
    _kind = kind;
    final key = store == null ? null : '$store/$kind';
    if (key == _watchKey) return;
    _watchKey = key;
    await _storeSub?.cancel();
    _storeSub = null;
    if (store == null) return;
    _storeSub = FirebaseFirestore.instance
        .collection('stores')
        .doc(store)
        .snapshots() // 문서 하나라 사용량 집계(metered)는 생략 (order_ready_overlay.dart와 같게)
        .listen(_onStore, onError: (e) => debugPrint('PadSessionGuard: $e'));
  }

  void _onStore(DocumentSnapshot<Map<String, dynamic>> snap) {
    final epoch = snap.data()?['authEpoch'];
    if (epoch is! Map) return;
    final v = epoch[_kind];
    final ms = v is num ? v : (v is Timestamp ? v.millisecondsSinceEpoch : null);
    if (PadSessionGuard.isStale(authTimeSec: _authTime, epochMs: ms)) _kick();
  }

  Future<void> _kick() async {
    if (_kicking) return;
    _kicking = true;
    try {
      await _storeSub?.cancel();
      _storeSub = null;
      _watchKey = null;
      await AdminSession.signOutPad(); // 매장 아이디·방 번호는 남기고 자동 로그인은 끔
      PadShell.navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen(notice: PadSessionGuard.kickedNotice)),
        (_) => false,
      );
    } catch (e) {
      debugPrint('PadSessionGuard: 로그아웃 실패 $e');
    } finally {
      _kicking = false;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _storeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
