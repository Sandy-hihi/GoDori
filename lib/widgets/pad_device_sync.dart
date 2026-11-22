import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/services/pad_device_service.dart';

/// 매장 태블릿 설정을 태블릿에 맞춰 둠 (142차)
///
/// 패드(손님 방·관리자 패드 모두 — 토큰 pad·store)로 로그인한 안드로이드 앱이
/// stores/{매장}/settings/padDevice(누구나 읽기)를 구독하다가 autoLaunch가 바뀌면 태블릿에 저장.
/// 로그아웃해도 마지막 값은 태블릿에 남음(로그인 화면에서 켜져도 그대로). 웹·윈도우 앱에서는 아무것도 안 함.
/// main.dart 의 MaterialApp.builder 에서 감쌈.
class PadDeviceSync extends StatefulWidget {
  final Widget child;
  const PadDeviceSync({super.key, required this.child});

  @override
  State<PadDeviceSync> createState() => _PadDeviceSyncState();
}

class _PadDeviceSyncState extends State<PadDeviceSync> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _store;
  bool? _applied;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    if (!PadDeviceService.deviceSupported) return;
    try {
      _authSub = FirebaseAuth.instance.idTokenChanges().listen(_onUser);
    } catch (_) {}
  }

  Future<void> _onUser(User? user) async {
    final gen = ++_gen;
    String? store;
    if (user != null) {
      try {
        final claims = await tokenClaimsOf(user);
        if (claims?['pad'] == true && claims?['store'] is String) store = claims!['store'] as String;
      } catch (_) {
        return;
      }
    }
    if (gen != _gen || store == _store) return;
    _store = store;
    await _sub?.cancel();
    _sub = null;
    if (store == null) return; // 로그아웃 — 태블릿 값은 그대로 둠
    // 문서 하나라 사용량 집계(metered)는 생략
    _sub = FirebaseFirestore.instance
        .collection('stores')
        .doc(store)
        .collection('settings')
        .doc('padDevice')
        .snapshots()
        .listen((s) {
      final on = PadDeviceService.parseAutoLaunch(s.data());
      if (on == _applied) return;
      _applied = on;
      PadDeviceService.applyToDevice(on);
    }, onError: (e) => debugPrint('PadDeviceSync: $e'));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
