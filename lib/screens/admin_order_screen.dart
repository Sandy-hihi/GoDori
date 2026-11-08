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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2B3C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2B3C),
        title: const Text('주문현황', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // 지금 매장의 음식 수령 방식 (관리자 웹 '매장 설정'에서 바꿈). 이미 들어온 주문은 주문할 때의 방식대로
          StreamBuilder<OrderFlow>(
            stream: OrderFlowService.watch(),
            builder: (context, snap) {
              final flow = snap.data;
              if (flow == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('수령 방식: ${flow.title}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 직원 호출 섹션 ──
          StreamBuilder<QuerySnapshot>(
            stream: StoreScope.col('staff_calls')
                .where('isAcknowledged', isEqualTo: false)
                .snapshots()
                .metered(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox.shrink();
              }
              final calls = snapshot.data!.docs.toList()
                ..sort((a, b) {
                  final aTs = (a.data() as Map)['timestamp'];
                  final bTs = (b.data() as Map)['timestamp'];
                  if (aTs == null || bTs == null) return 0;
                  return (bTs as Timestamp).compareTo(aTs as Timestamp);
                });
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('직원 호출', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  ...calls.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final room = data['roomNumber']?.toString() ?? '?';
                    final ts = data['timestamp'];
                    String timeStr = '';
                    if (ts != null && ts is Timestamp) {
                      final dt = ts.toDate().toLocal();
                      final h = dt.hour.toString().padLeft(2, '0');
                      final m = dt.minute.toString().padLeft(2, '0');
                      timeStr = '$h:$m';
                    }
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: Colors.orangeAccent, width: 1.5),
                        boxShadow: [
                          BoxShadow(color: Colors.orange.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        children: [
                          // 왼쪽: 방 번호
                          Container(
                            width: 80,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE67E22),
                              borderRadius: BorderRadius.horizontal(left: Radius.circular(6.5)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(room, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                                if (timeStr.isNotEmpty)
                                  Text(timeStr, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ),
                          // 중앙: 안내 문구
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Icon(Icons.notifications_active, color: Color(0xFFE67E22), size: 22),
                                  SizedBox(width: 8),
                                  Text('직원 호출', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
                                ],
                              ),
                            ),
                          ),
                          // 오른쪽: 확인 버튼
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: ElevatedButton(
                              onPressed: () => _acknowledgeCall(doc.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE67E22),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              ),
                              child: const Text('확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(color: Colors.white24, height: 1),
                ],
              );
            },
          ),

          // ── 주문 목록 섹션 ──
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: StoreScope.col('orders')
                  .orderBy('timestamp', descending: true)
                  .snapshots()
                  .metered(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('대기 중인 주문이 없습니다.', style: TextStyle(color: Colors.white, fontSize: 18)));
                }

                final orders = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final doc = orders[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final docId = doc.id;

                    final String statusStr = (data['status'] ?? 'pending').toString();
                    final flow = OrderFlow.parse(data['flow']); // 없으면(예전 주문) 서빙
                    final isCompleted = statusStr == 'completed';
                    final isReady = statusStr == 'ready';

                    final items = data['items'] as List<dynamic>? ?? [];

                    // 폰 세로(폭 600 미만): 위아래로 쌓는 카드 — 가로 고정폭(방 100·가격 120·버튼 132)이 375px에 안 들어가서 (80차)
                    if (MediaQuery.sizeOf(context).width < 600) {
                      return _compactOrderCard(
                        docId: docId,
                        data: data,
                        statusStr: statusStr,
                        flow: flow,
                        isCompleted: isCompleted,
                        isReady: isReady,
                        items: items,
                      );
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8.0),
                        // 준비 완료(손님이 받으러 오는 중)는 초록 테두리
                        border: isReady ? Border.all(color: const Color(0xFF27AE60), width: 2.5) : null,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, 2))
                        ],
                      ),
                      height: 140,
                      child: Row(
                        children: [
                          // 왼쪽: 방 번호
                          Container(
                            width: 100,
                            decoration: BoxDecoration(
                              color: isCompleted ? Colors.black87 : Color((data['roomColor'] as int?) ?? 0xFFC2365A),
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(8.0)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(data['room'] ?? '#?', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                                const SizedBox(height: 4),
                                Text(data['time'] ?? '', style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 6),
                                Text(flow.statusText(statusStr),
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                if (flow.isPickup)
                                  Text(flow.badge, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ),
                          // 중앙: 가격 및 메뉴
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 120,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("${data['price']} 원", style: TextStyle(fontSize: 22, color: isCompleted ? Colors.grey : Colors.black87, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        // 토스 POS로 보냈는지 (64차, 연동 안 쓰는 매장은 안 보임)
                                        TossSendBadge(
                                          orderId: docId,
                                          tossPos: data['tossPos'] is Map ? Map<String, dynamic>.from(data['tossPos'] as Map) : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: ListView.builder(
                                            physics: const NeverScrollableScrollPhysics(),
                                            itemCount: items.length,
                                            itemBuilder: (context, i) {
                                              return Text(items[i].toString(), style: TextStyle(fontSize: 16, color: isCompleted ? Colors.grey : Colors.black87));
                                            },
                                          ),
                                        ),
                                        Divider(color: Colors.grey[300]),
                                        Text(data['notes'] ?? '', style: TextStyle(fontSize: 12, color: isCompleted ? Colors.grey : Colors.grey[600])),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 오른쪽: 상태 변경 버튼
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Center(
                              child: _buildStatusButton(docId, statusStr, flow),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
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
    final Size? fixed = compact ? null : const Size(132, 72);
    final Size minimum = compact ? const Size.fromHeight(52) : const Size(132, 72);
    if (currentStatus == 'completed') {
      return ElevatedButton(
        onPressed: () => _deleteOrder(docId),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          fixedSize: fixed,
          minimumSize: minimum,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        ),
        child: const Text('삭제', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      );
    }

    final Color color = switch (currentStatus) {
      'pending' => const Color(0xFFE67E22),
      'ready' => const Color(0xFF27AE60),
      _ => const Color(0xFFD35400),
    };
    return ElevatedButton(
      onPressed: () => _toggleOrderStatus(docId, currentStatus, flow),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        fixedSize: fixed,
        minimumSize: minimum,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
      child: Text(flow.buttonLabel(currentStatus),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, height: 1.25)),
    );
  }
}
