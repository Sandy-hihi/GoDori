import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/services/store_features.dart';
import 'package:boardpad/widgets/pad_shell.dart';

/// 손님 패드: 30분 동안 아무도 화면을 안 만지면 홈 화면으로 (140차)
///
/// 토스 POS 연동 매장은 방 결제가 끝나면 홈으로 돌아가지만(82차 order_ready_overlay.dart),
/// 연동을 안 하는 매장은 손님이 떠나도 패드가 마지막 화면(장바구니·게임 상세 등) 그대로 남음.
/// 그래서 연동 안 한 매장(features.tossPos == false)만, 손님 방 패드(토큰 pad·room ≥ 1)에서
/// 마지막 터치 뒤 [idleLimit]가 지나면 위에 뜬 창·내부 화면을 모두 닫고 홈으로 + 언어를 로그인 때 고른 언어로.
/// - 관리자 패드(방 0)·로그인 화면·관리자 웹에서는 아무것도 안 함
/// - 게임도구 타이머·스톱워치가 돌거나 룰 영상이 재생 중이면 기다림([hold]) — 끝난 뒤부터 다시 30분
/// main.dart 의 MaterialApp.builder 에서 모든 화면을 감쌈.
class PadIdleHome extends StatefulWidget {
  final Widget child;
  const PadIdleHome({super.key, required this.child});

  static const idleLimit = Duration(minutes: 30);

  static final Set<Object> _holds = {};

  /// 돌아가는 동안엔 홈으로 보내지 않음 (타이머·스톱워치·영상 재생)
  static void hold(Object owner) => _holds.add(owner);
  static void release(Object owner) => _holds.remove(owner);

  /// 홈으로 보낼 때인지 (테스트용으로 따로 뺌)
  static bool shouldGoHome({
    required DateTime lastActivity,
    required DateTime now,
    required bool guestPad,
    required bool? tossPos, // null = 아직 모름 → 보내지 않음
    required bool held,
    Duration limit = idleLimit,
  }) =>
      guestPad && tossPos == false && !held && now.difference(lastActivity) >= limit;

  @override
  State<PadIdleHome> createState() => _PadIdleHomeState();
}

class _PadIdleHomeState extends State<PadIdleHome> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _storeSub;
  Timer? _check;
  DateTime _last = DateTime.now();
  String? _store; // 손님 방 패드로 로그인한 매장 (아니면 null)
  bool? _tossPos;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    try {
      _authSub = FirebaseAuth.instance.idTokenChanges().listen(_onUser);
    } catch (_) {
      // Firebase 초기화 전(테스트 등) — 아무것도 안 함
    }
    _check = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  Future<void> _onUser(User? user) async {
    final gen = ++_gen;
    String? store;
    if (user != null) {
      try {
        final claims = await tokenClaimsOf(user);
        final r = claims?['room'];
        if (claims?['pad'] == true && claims?['store'] is String && r is num && r >= 1) {
          store = claims!['store'] as String;
        }
      } catch (_) {
        return; // 토큰을 잠깐 못 읽음(인터넷 끊김 등) — 지금 상태 그대로
      }
    }
    if (gen != _gen || store == _store) return;
    _store = store;
    _tossPos = null;
    _last = DateTime.now();
    await _storeSub?.cancel();
    _storeSub = null;
    if (store == null) return;
    // 매장 문서(누구나 읽기) — 운영자가 토스 연동을 켜고 끄면 바로 따라감. 문서 하나라 사용량 집계(metered)는 생략
    _storeSub = FirebaseFirestore.instance.collection('stores').doc(store).snapshots().listen(
          (s) => _tossPos = StoreFeatures.fromStoreData(s.data()).tossPos,
          onError: (e) => debugPrint('PadIdleHome: $e'),
        );
  }

  void _touched() => _last = DateTime.now();

  void _tick() {
    final now = DateTime.now();
    if (PadIdleHome._holds.isNotEmpty) {
      _last = now; // 타이머·영상이 끝난 뒤부터 다시 셈
      return;
    }
    if (!PadIdleHome.shouldGoHome(
      lastActivity: _last,
      now: now,
      guestPad: _store != null,
      tossPos: _tossPos,
      held: false,
    )) {
      return;
    }
    _last = now;
    GuestLanguage.instance.resetToDefault();
    PadShell.goHome();
  }

  @override
  void dispose() {
    _check?.cancel();
    _authSub?.cancel();
    _storeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 화면 어디를 만지든(스크롤·끌기 포함) 마지막 터치 시각만 고침 — 터치를 가로채지 않음
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touched(),
      onPointerMove: (_) => _touched(),
      onPointerSignal: (_) => _touched(),
      child: widget.child,
    );
  }
}
