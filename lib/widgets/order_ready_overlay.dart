import 'package:boardpad/l10n/guest_language.dart';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:boardpad/models/order_flow.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/services/usage_meter.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_shell.dart';

/// 손님 패드: 주문한 음식이 '준비 완료'되면 알림 (58차 — 카운터에서 받아 가는 매장)
///
/// main.dart 의 MaterialApp.builder 에서 모든 화면 위에 덮어 씀 → 손님이 어느 화면에 있든 뜸.
/// - 방 패드로 로그인했을 때만(토큰 pad·store·room) 자기 방 주문 중 status == 'ready' 를 구독
///   (firestore.rules: 패드는 자기 방 주문만 읽기 — where('room') 필수)
/// - 새로 준비된 주문이 오면 알림 소리(assets/sounds/order_ready.mp3) + 큰 알림 창. '확인'으로 닫아도 위쪽에 작은 띠가 남고,
///   관리자가 주문현황에서 '받아 감'/'결제·전달 완료'를 누르면 사라짐
/// - 관리자 토큰(방 0)·로그아웃 상태에서는 아무것도 안 함
/// - 81차: 자기 방 roomStatus 문서도 구독 — 토스 포스에서 그 방 패드 주문이 다 결제되면(settledAt이 바뀜)
///   손님이 바꾼 언어를 로그인 때 고른 언어로 되돌리고 홈 화면으로 돌아감(82차). 토스 연동을 안 하는 매장은 문서가 안 생겨서 아무 일 없음
/// - 97차: 엉뚱한 때 '똑똑똑' 소리가 나던 문제 — 소리를 낸 주문 번호를 패드에 저장(_rungPrefKey)해서
///   새로 켜기·새로고침·다시 로그인·토큰 갱신 때 이미 울린 주문으로 다시 울리지 않음(창·띠는 그대로 보임).
///   토큰을 읽다 잠깐 실패해도(인터넷 끊김 등) 구독을 끊지 않음 — 예전엔 끊었다가 다시 구독하면서 소리가 또 났음
class OrderReadyOverlay extends StatefulWidget {
  final Widget child;
  const OrderReadyOverlay({super.key, required this.child});

  @override
  State<OrderReadyOverlay> createState() => _OrderReadyOverlayState();
}

class _ReadyOrder {
  final String id;
  final OrderFlow flow;
  final String price;
  final List<String> items;
  const _ReadyOrder(this.id, this.flow, this.price, this.items);
}

class _OrderReadyOverlayState extends State<OrderReadyOverlay> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _orderSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;
  Object? _settledSeen; // 처음 받은 settledAt (켤 때 이미 있던 값으로는 되돌리지 않음)
  bool _roomFirst = true;
  String? _watchKey; // '매장/방' — 토큰이 새로 고쳐져도 같은 방이면 다시 구독하지 않음
  int _gen = 0; // _onUser가 겹쳐 불릴 때 늦게 끝난 예전 호출은 무시
  final _player = AudioPlayer();

  List<_ReadyOrder> _ready = [];
  final Set<String> _rung = {}; // 소리를 이미 낸 주문
  final Set<String> _dismissed = {}; // 큰 창을 '확인'으로 닫은 주문

  @override
  void initState() {
    super.initState();
    try {
      _authSub = FirebaseAuth.instance.idTokenChanges().listen(_onUser);
    } catch (_) {
      // Firebase 초기화 전(테스트 등) — 알림 없이
    }
  }

  static String _rungPrefKey(String watchKey) => 'orderReadyRung/$watchKey';

  Future<void> _onUser(User? user) async {
    final gen = ++_gen;
    String? store;
    int? room;
    if (user != null) {
      try {
        final claims = await tokenClaimsOf(user); // 윈도우 앱에서도 읽히게
        final r = claims?['room'];
        if (claims?['pad'] == true && claims?['store'] is String && r is num && r >= 1) {
          store = claims!['store'] as String;
          room = r.toInt();
        }
      } catch (_) {
        // 97차: 토큰을 잠깐 못 읽음(인터넷 끊김 등) — 로그아웃이 아니니 지금 구독을 그대로 둠
        return;
      }
    }
    if (gen != _gen) return;
    final key = (store != null && room != null) ? '$store/$room' : null;
    if (key == _watchKey) return;
    _watchKey = key;
    await _orderSub?.cancel();
    _orderSub = null;
    await _roomSub?.cancel();
    _roomSub = null;
    _roomFirst = true;
    _settledSeen = null;
    if (mounted) {
      setState(() {
        _ready = [];
        _rung.clear();
        _dismissed.clear();
      });
    }
    if (store == null || room == null) return;
    // 97차: 이 방 패드에서 이미 소리를 낸 주문 — 새로 켜거나 새로고침해도 다시 울리지 않게
    try {
      final prefs = await SharedPreferences.getInstance();
      _rung.addAll(prefs.getStringList(_rungPrefKey(key!)) ?? const []);
    } catch (_) {}
    if (gen != _gen || key != _watchKey) return;
    _orderSub = FirebaseFirestore.instance
        .collection('stores')
        .doc(store)
        .collection('orders')
        .where('room', isEqualTo: '#$room')
        .where('status', isEqualTo: 'ready')
        .snapshots()
        .metered()
        .listen(_onOrders, onError: (e) => debugPrint('OrderReadyOverlay: $e'));
    _roomSub = FirebaseFirestore.instance
        .collection('stores')
        .doc(store)
        .collection('roomStatus')
        .doc('$room')
        .snapshots() // 문서 하나라 사용량 집계(metered)는 생략
        .listen(_onRoomStatus, onError: (e) => debugPrint('OrderReadyOverlay roomStatus: $e'));
  }

  void _onRoomStatus(DocumentSnapshot<Map<String, dynamic>> snap) {
    final settled = snap.data()?['settledAt'];
    if (_roomFirst) {
      _roomFirst = false;
      _settledSeen = settled;
      return;
    }
    if (settled != null && settled != _settledSeen) {
      _settledSeen = settled;
      GuestLanguage.instance.resetToDefault();
      PadShell.goHome(); // 82차: 다음 손님을 위해 홈 화면으로
    }
  }

  void _onOrders(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map((d) {
      final data = d.data();
      return _ReadyOrder(
        d.id,
        OrderFlow.parse(data['flow']),
        (data['price'] ?? '').toString(),
        ((data['items'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
    }).toList();
    final ids = list.map((o) => o.id).toSet();
    final fresh = ids.difference(_rung);
    if (fresh.isNotEmpty) {
      // 손님용 소리 (관리자 패드의 ddingdong.mp3와 구분, 59차)
      _player.play(AssetSource('sounds/order_ready.mp3')).catchError((_) {});
      _rung.addAll(fresh);
    }
    _dismissed.retainAll(ids);
    final before = _rung.length;
    _rung.retainAll(ids);
    if (fresh.isNotEmpty || _rung.length != before) _saveRung();
    if (mounted) setState(() => _ready = list);
  }

  // 지금 '준비 완료' 상태인 주문 중 소리를 낸 것만 저장 (끝난 주문은 빠지므로 쌓이지 않음)
  Future<void> _saveRung() async {
    final key = _watchKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_rungPrefKey(key), _rung.toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _orderSub?.cancel();
    _roomSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showBig = _ready.any((o) => !_dismissed.contains(o.id));
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_ready.isNotEmpty && !showBig)
          Positioned(top: 12, left: 0, right: 0, child: Center(child: _banner())),
        if (showBig) Positioned.fill(child: _bigCard()),
      ],
    );
  }

  // 여러 주문이 동시에 준비되면 한 번에 보여 줌 (결제 금액은 합계)
  OrderFlow get _flow => _ready.isEmpty ? OrderFlow.pickup : _ready.first.flow;

  String get _totalPrice {
    int sum = 0;
    for (final o in _ready) {
      if (!o.flow.payAtPickup) continue;
      sum += int.tryParse(o.price.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    }
    return sum > 0 ? '$sum' : '';
  }

  Widget _banner() {
    final flow = _flow;
    return Material(
      color: kOrange,
      elevation: 6,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => setState(_dismissed.clear),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.room_service_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              GuestText(
                flow.payAtPickup ? '음식이 준비됐어요 · 카운터에서 결제하고 받아 가 주세요' : '음식이 준비됐어요 · 카운터에서 받아 가 주세요',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigCard() {
    final flow = _flow;
    final items = [for (final o in _ready) ...o.items];
    const maxLines = 5;
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          width: 540,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(color: kOrange.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(flow.payAtPickup ? Icons.payments_rounded : Icons.room_service_rounded,
                    color: kOrange, size: 50),
              ),
              const SizedBox(height: 18),
              const GuestText('주문하신 음식이 준비됐어요!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kInk)),
              const SizedBox(height: 8),
              GuestText(flow.readyText(_totalPrice),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: kBody, height: 1.4)),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final it in items.take(maxLines))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: GuestText(it,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, color: kInk, fontWeight: FontWeight.w600)),
                        ),
                      if (items.length > maxLines)
                        GuestText('외 ${items.length - maxLines}개', style: const TextStyle(fontSize: 14, color: kMuted)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                height: 56,
                child: FilledButton(
                  onPressed: () => setState(() => _dismissed.addAll(_ready.map((o) => o.id))),
                  style: FilledButton.styleFrom(
                    backgroundColor: kOrange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const GuestText('확인했어요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
