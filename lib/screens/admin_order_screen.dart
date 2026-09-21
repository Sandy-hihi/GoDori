import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';

class AdminOrderScreen extends StatefulWidget {
  const AdminOrderScreen({super.key});

  @override
  State<AdminOrderScreen> createState() => _AdminOrderScreenState();
}

// 상태 관리를 위한 열거형
enum OrderStatus { pending, preparing, completed }

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
    _callSubscription = FirebaseFirestore.instance
        .collection('staff_calls')
        .where('isAcknowledged', isEqualTo: false)
        .snapshots()
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
    _orderSubscription = FirebaseFirestore.instance
        .collection('orders')
        .where('status', isEqualTo: 'pending')
        .snapshots()
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
  Future<void> _toggleOrderStatus(String docId, String currentStatus) async {
    String nextStatus = 'pending';
    if (currentStatus == 'pending') {
      nextStatus = 'preparing';
    } else if (currentStatus == 'preparing') {
      nextStatus = 'completed';
    }

    await FirebaseFirestore.instance.collection('orders').doc(docId).update({
      'status': nextStatus,
    });
  }

  // 2. 주문 삭제 함수
  Future<void> _deleteOrder(String docId) async {
    await FirebaseFirestore.instance.collection('orders').doc(docId).delete();
  }

  // 직원 호출 확인 처리
  Future<void> _acknowledgeCall(String docId) async {
    await FirebaseFirestore.instance
        .collection('staff_calls')
        .doc(docId)
        .update({'isAcknowledged': true});
  }

  // 문자열을 Enum으로 변환하는 헬퍼 함수
  OrderStatus _parseStatus(String statusStr) {
    if (statusStr == 'preparing') return OrderStatus.preparing;
    if (statusStr == 'completed') return OrderStatus.completed;
    return OrderStatus.pending;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2B3C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2B3C),
        title: const Text('주문현황', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ── 직원 호출 섹션 ──
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('staff_calls')
                .where('isAcknowledged', isEqualTo: false)
                .snapshots(),
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
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
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

                    final statusStr = data['status'] ?? 'pending';
                    final status = _parseStatus(statusStr);
                    final isCompleted = status == OrderStatus.completed;

                    final items = data['items'] as List<dynamic>? ?? [];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8.0),
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
                                const SizedBox(height: 8),
                                Text(data['time'] ?? '', style: const TextStyle(color: Colors.white70)),
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
                                    child: Text("${data['price']} 원", style: TextStyle(fontSize: 22, color: isCompleted ? Colors.grey : Colors.black87, fontWeight: FontWeight.bold)),
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
                              child: _buildStatusButton(status, docId, statusStr, data['room'] ?? ''),
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

  // 3. 상태 버튼 위젯
  Widget _buildStatusButton(OrderStatus status, String docId, String currentStatus, String roomName) {
    if (status == OrderStatus.completed) {
      return ElevatedButton(
        onPressed: () => _deleteOrder(docId),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        ),
        child: const Text('삭제', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      );
    }

    if (status == OrderStatus.pending) {
      return ElevatedButton(
        onPressed: () => _toggleOrderStatus(docId, currentStatus),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE67E22),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        ),
        child: const Text('준비', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      );
    }

    return ElevatedButton(
      onPressed: () => _toggleOrderStatus(docId, currentStatus),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD35400),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
      child: const Text('준비중..', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}
