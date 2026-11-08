import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:boardpad/models/order_flow.dart';
import 'package:boardpad/services/order_flow_service.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/usage_meter.dart';
import 'package:boardpad/widgets/toss_send_badge.dart';

class AdminOrderScreen extends StatefulWidget {
  const AdminOrderScreen({super.key});

  @override
  State<AdminOrderScreen> createState() => _AdminOrderScreenState();
}

class _AdminOrderScreenState extends State<AdminOrderScreen> {
  final _audioPlayer = AudioPlayer();
  StreamSubscription? _callSubscription;
  bool _isInitialLoad = true;
  StreamSubscription? _orderSubscription;
  bool _isOrderInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _listenForStaffCalls();
    _listenForOrders();
  }

  void _listenForStaffCalls() {
    _callSubscription = StoreScope.col('staff_calls')
        .where('isAcknowledged', isEqualTo: false)
        .snapshots()
        .metered()
        .listen((snapshot) {
      if (_isInitialLoad) {
        _isInitialLoad = false;
        return;
      }
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _audioPlayer.play(AssetSource('sounds/ddingdong.mp3'));
        }
      }
    });
  }

  void _listenForOrders() {
    _orderSubscription = StoreScope.col('orders')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .metered()
        .listen((snapshot) {
      if (_isOrderInitialLoad) {
        _isOrderInitialLoad = false;
        return;
      }
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _audioPlayer.play(AssetSource('sounds/ddingdong.mp3'));
          break;
        }
      }
    });
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _orderSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // 1. 상태 변경 함수 (Firestore 실시간 업데이트)
  // 다음 상태는 주문의 수령 방식(flow)에 따라 다름 — models/order_flow.dart (58차)
  //   서빙: 접수 → 준비중 → 완료 / 카운터 수령: 접수 → 준비중 → 준비 완료(패드 알림) → 완료
  Future<void> _toggleOrderStatus(String docId, String currentStatus, OrderFlow flow) async {
    final next = flow.nextStatus(currentStatus);
    if (next == null) return;
    await StoreScope.col('orders').doc(docId).update({
      'status': next,
      // 카운터 결제 후 수령: 전달 완료 = 결제도 끝 (나중에 매출 통계에서 씀)
      if (next == 'completed' && flow.payAtPickup) 'paid': true,
    });
  }

  // 2. 주문 삭제 함수
  Future<void> _deleteOrder(String docId) async {
    await StoreScope.col('orders').doc(docId).delete();
  }

  // 직원 호출 확인 처리
  Future<void> _acknowledgeCall(String docId) async {
    await StoreScope.col('staff_calls')
        .doc(docId)
        .update({'isAcknowledged': true});
  }

  // ── 화면 (82차: 손님 패드와 같은 크림 톤, 아이패드 가로는 2열 카드) ──
  static const _bg = Color(0xFFF4F0E8);
  static const _ink = Color(0xFF26211C);
  static const _muted = Color(0xFF7A7266);
  static const _line = Color(0xFFE6E1D7);
  static const _orange = Color(0xFFE2711D);
  static const _green = Color(0xFF1F9D63);
  static const _navy = Color(0xFF1E2B3C);

  Color _statusColor(String status) => switch (status) {
        'pending' => _orange,
        'preparing' => const Color(0xFFB85C1A),
        'ready' => _green,
        _ => _muted,
      };

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool phone = width < 600;
    final int columns = width >= 1100 ? 2 : 1;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: StoreScope.col('orders').orderBy('timestamp', descending: true).snapshots().metered(),
                builder: (context, orderSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: StoreScope.col('staff_calls').where('isAcknowledged', isEqualTo: false).snapshots().metered(),
                    builder: (context, callSnap) {
                      if (orderSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: _orange));
                      }
                      final calls = (callSnap.data?.docs ?? []).toList()
                        ..sort((a, b) {
                          final aTs = (a.data() as Map)['timestamp'];
                          final bTs = (b.data() as Map)['timestamp'];
                          if (aTs == null || bTs == null) return 0;
                          return (bTs as Timestamp).compareTo(aTs as Timestamp);
                        });
                      final orders = orderSnap.data?.docs ?? [];
                      final active = orders.where((d) => ((d.data() as Map)['status'] ?? 'pending') != 'completed').length;

                      if (orders.isEmpty && calls.isEmpty) return _empty();

                      return CustomScrollView(
                        slivers: [
                          if (calls.isNotEmpty) ...[
                            _sectionTitle('직원 호출', calls.length, _orange),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(phone ? 12 : 24, 0, phone ? 12 : 24, 8),
                              sliver: SliverList.separated(
                                itemCount: calls.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) => _callCard(calls[i]),
                              ),
                            ),
                          ],
                          _sectionTitle('주문', active, _navy, suffix: active == orders.length ? null : '완료 ${orders.length - active}'),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(phone ? 12 : 24, 0, phone ? 12 : 24, 32),
                            sliver: phone
                                ? SliverList.builder(
                                    itemCount: orders.length,
                                    itemBuilder: (context, i) => _orderTile(orders[i], phone: true),
                                  )
                                : SliverGrid(
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisSpacing: 14,
                                      crossAxisSpacing: 14,
                                      mainAxisExtent: 176,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, i) => _orderTile(orders[i], phone: false),
                                      childCount: orders.length,
                                    ),
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final now = DateTime.now();
    final date = '${now.month}월 ${now.day}일';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 10),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: _line))),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: _ink),
            tooltip: '나가기',
          ),
          const SizedBox(width: 4),
          const Text('주문현황', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.3)),
          const SizedBox(width: 10),
          Text(date, style: const TextStyle(fontSize: 14, color: _muted)),
          const Spacer(),
          StreamBuilder<OrderFlow>(
            stream: OrderFlowService.watch(),
            builder: (context, snap) {
              final flow = snap.data;
              if (flow == null) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: _line)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.room_service_outlined, size: 16, color: _muted),
                    const SizedBox(width: 6),
                    Text('수령 방식 · ${flow.title}', style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, int count, Color color, {String? suffix}) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            if (suffix != null) ...[
              const SizedBox(width: 10),
              Text(suffix, style: const TextStyle(fontSize: 13, color: _muted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _line)),
            child: const Icon(Icons.inbox_outlined, color: _muted, size: 34),
          ),
          const SizedBox(height: 14),
          const Text('대기 중인 주문이 없어요', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('손님이 주문하면 소리와 함께 여기에 떠요', style: TextStyle(color: _muted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _callCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final room = data['roomNumber']?.toString() ?? '?';
    String timeStr = '';
    final ts = data['timestamp'];
    if (ts is Timestamp) {
      final dt = ts.toDate().toLocal();
      timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return Container(
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _orange.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [BoxShadow(color: _orange.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 84,
            color: _orange,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$room번', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                if (timeStr.isNotEmpty) Text(timeStr, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.notifications_active_rounded, color: _orange, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('직원을 불렀어요', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink))),
          Padding(
            padding: const EdgeInsets.all(10),
            child: FilledButton(
              onPressed: () => _acknowledgeCall(doc.id),
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                minimumSize: const Size(96, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('확인', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderTile(QueryDocumentSnapshot doc, {required bool phone}) {
    final data = doc.data() as Map<String, dynamic>;
    final docId = doc.id;
    final String statusStr = (data['status'] ?? 'pending').toString();
    final flow = OrderFlow.parse(data['flow']);
    final isCompleted = statusStr == 'completed';
    final isReady = statusStr == 'ready';
    final items = data['items'] as List<dynamic>? ?? [];

    if (phone) {
      return _compactOrderCard(
        docId: docId, data: data, statusStr: statusStr, flow: flow,
        isCompleted: isCompleted, isReady: isReady, items: items,
      );
    }

    final Color roomColor = isCompleted ? const Color(0xFF9A948B) : Color((data['roomColor'] as int?) ?? 0xFFC2365A);
    final Color ink = isCompleted ? _muted : _ink;
    final String notes = (data['notes'] ?? '').toString().trim();
    final Color sc = _statusColor(statusStr);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isReady ? _green : _line, width: isReady ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 방 번호 띠
          Container(
            width: 96,
            color: roomColor,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text((data['room'] ?? '#?').toString(),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                const SizedBox(height: 6),
                Text((data['time'] ?? '').toString(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          // 본문
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text(flow.statusText(statusStr),
                            style: TextStyle(color: sc, fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                      if (flow.isPickup) ...[
                        const SizedBox(width: 6),
                        Text(flow.badge, style: const TextStyle(color: _muted, fontSize: 12)),
                      ],
                      const Spacer(),
                      Text("${data['price']}원", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      physics: const ClampingScrollPhysics(),
                      children: [
                        for (final it in items)
                          Text(it.toString(), style: TextStyle(fontSize: 15, color: ink, height: 1.35)),
                        if (notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('메모 · $notes', style: const TextStyle(fontSize: 12.5, color: _muted)),
                          ),
                      ],
                    ),
                  ),
                  TossSendBadge(
                    orderId: docId,
                    tossPos: data['tossPos'] is Map ? Map<String, dynamic>.from(data['tossPos'] as Map) : null,
                  ),
                ],
              ),
            ),
          ),
          // 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
            child: Center(child: _buildStatusButton(docId, statusStr, flow)),
          ),
        ],
      ),
    );
  }

  // 폰 세로용 주문 카드: [방 번호·시간·상태] 머리 → 메뉴·요청사항 → 금액 → 꽉 찬 버튼
  Widget _compactOrderCard({
    required String docId,
    required Map<String, dynamic> data,
    required String statusStr,
    required OrderFlow flow,
    required bool isCompleted,
    required bool isReady,
    required List<dynamic> items,
  }) {
    final Color roomColor = isCompleted ? Colors.black87 : Color((data['roomColor'] as int?) ?? 0xFFC2365A);
    final Color ink = isCompleted ? Colors.grey : Colors.black87;
    final String notes = (data['notes'] ?? '').toString().trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isReady ? Border.all(color: const Color(0xFF27AE60), width: 2.5) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 머리: 방 번호 · 주문 시각 · 상태
          Container(
            color: roomColor,
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Text((data['room'] ?? '#?').toString(),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(width: 10),
                Text((data['time'] ?? '').toString(), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    flow.isPickup ? '${flow.statusText(statusStr)} · ${flow.badge}' : flow.statusText(statusStr),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          // 본문: 메뉴 → 요청사항 → 금액
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(it.toString(), style: TextStyle(fontSize: 16, color: ink, height: 1.3)),
                  ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFFF4F5F7), borderRadius: BorderRadius.circular(8)),
                    child: Text(notes, style: TextStyle(fontSize: 13, color: isCompleted ? Colors.grey : Colors.grey[700])),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text("${data['price']} 원", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: TossSendBadge(
                        orderId: docId,
                        tossPos: data['tossPos'] is Map ? Map<String, dynamic>.from(data['tossPos'] as Map) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 아래: 상태 변경 버튼 (가로 꽉 차게)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _buildStatusButton(docId, statusStr, flow, compact: true),
          ),
        ],
      ),
    );
  }

  // 3. 상태 버튼 위젯 (글자·다음 상태는 수령 방식에 따라 — models/order_flow.dart)
  // compact: 폰 세로 카드에서 가로 꽉 찬 52px 버튼
  Widget _buildStatusButton(String docId, String currentStatus, OrderFlow flow, {bool compact = false}) {
    final Size? fixed = compact ? null : const Size(128, 64);
    final Size minimum = compact ? const Size.fromHeight(52) : const Size(128, 64);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    if (currentStatus == 'completed') {
      // 완료된 주문: 눈에 덜 띄는 테두리 버튼 (실수로 지우지 않게)
      return OutlinedButton.icon(
        onPressed: () => _deleteOrder(docId),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFC0392B),
          side: const BorderSide(color: Color(0xFFE6B0AA)),
          fixedSize: fixed,
          minimumSize: minimum,
          shape: shape,
        ),
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('삭제', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );
    }
    final Color color = switch (currentStatus) {
      'pending' => _orange,
      'ready' => _green,
      _ => _navy,
    };
    return FilledButton(
      onPressed: () => _toggleOrderStatus(docId, currentStatus, flow),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        fixedSize: fixed,
        minimumSize: minimum,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: shape,
      ),
      child: Text(flow.buttonLabel(currentStatus),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25)),
    );
  }
}
