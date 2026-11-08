import 'dart:async';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:boardpad/models/order_flow.dart' show wonText;
import 'package:boardpad/models/order_history.dart';
import 'package:boardpad/services/store_features.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/usage_meter.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/home_common.dart';
import 'package:boardpad/widgets/pad_shell.dart';

/// 손님 패드 '주문 내역' (84차) — 사이드바 '메뉴 바로가기'에서 사장님이 넣고 뺌 (홈 화면 꾸미기)
///
/// - 토스 POS 연동 매장(features.tossPos)에서만: 방 전체 결제가 끝나면 서버가 목록을 비워서
///   다음 손님에게 앞 손님 주문이 안 보임. 연동 안 한 매장은 안내만 (사이드바 메뉴에도 안 보임)
/// - 목록 = roomStatus/{방}.cycle (서버가 포스로 들어간 주문만 넣음 — 포스 보내기 실패한 주문은
///   관리자가 '다시 보내기' 한 뒤에 보임)
/// - 준비 상태 = 그 방의 진행 중 주문(pending·preparing·ready) — 목록에 없으면 '전달 완료'
/// - 일행 중 먼저 결제한 주문은 '결제됨'으로 남김, 포스에서 취소된 주문은 '취소됨'
class OrderHistoryScreen extends StatefulWidget {
  final int? roomNumber;
  const OrderHistoryScreen({super.key, this.roomNumber});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  int get _room => widget.roomNumber ?? 1;

  late final Stream<StoreFeatures> _features = StoreFeaturesService.watch();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _roomStatus =
      StoreScope.col('roomStatus').doc('$_room').snapshots(); // 문서 하나 — metered 생략
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _active = StoreScope.col('orders')
      .where('room', isEqualTo: '#$_room') // 보안 규칙: 패드는 자기 방 주문만 (이 조건 필수)
      .where('status', whereIn: const ['pending', 'preparing', 'ready'])
      .snapshots()
      .metered();

  // 메뉴 이름·옵션 번역용 (83차 translations) — 한 번만 읽음
  Map<String, Map<String, dynamic>> _menus = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadMenus());
  }

  Future<void> _loadMenus() async {
    try {
      final snap = await StoreScope.col('menus').get().metered();
      if (!mounted) return;
      setState(() => _menus = {for (final d in snap.docs) d.id: d.data()});
    } catch (_) {
      /* 번역 없이 원래 이름으로 보여 줌 */
    }
  }

  @override
  Widget build(BuildContext context) {
    return PadShell(
      current: 'orders',
      roomNumber: widget.roomNumber,
      title: '주문 내역',
      subtitle: '이번에 주문한 메뉴예요 · 결제가 모두 끝나면 비워져요',
      body: StreamBuilder<StoreFeatures>(
        stream: _features,
        builder: (context, f) {
          if (!f.hasData) return const Center(child: CircularProgressIndicator(color: kOrange));
          if (!f.data!.tossPos) {
            return const PadEmpty(icon: Icons.receipt_long_outlined, text: '이 매장에서는 주문 내역을 볼 수 없어요.');
          }
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _roomStatus,
            builder: (context, r) {
              if (r.hasError) {
                return const PadEmpty(icon: Icons.receipt_long_outlined, text: '주문 내역을 불러오지 못했어요.');
              }
              if (!r.hasData) return const Center(child: CircularProgressIndicator(color: kOrange));
              final list = OrderHistoryEntry.listFrom(r.data!.data());
              if (list.isEmpty) {
                return const PadEmpty(icon: Icons.receipt_long_outlined, text: '아직 주문한 메뉴가 없어요.');
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _active,
                builder: (context, a) {
                  final active = <String, Map<String, dynamic>>{
                    for (final d in a.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      d.id: d.data(),
                  };
                  return _body(context, list, active, statusKnown: a.hasData);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<OrderHistoryEntry> list,
    Map<String, Map<String, dynamic>> active, {
    required bool statusKnown,
  }) {
    final totals = orderHistoryTotals(list);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final e = list[i];
              final order = active[e.id];
              return _OrderCard(
                entry: e,
                // 진행 중 목록을 아직 못 받았으면 상태 칸을 비움 (잠깐 '전달 완료'로 깜빡이지 않게)
                status: !statusKnown ? null : order?['status']?.toString() ?? 'completed',
                menus: _menus,
              );
            },
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(32, 0, 32, 22),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kLine),
          ),
          child: Row(
            children: [
              const GuestText('주문 합계', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kBody)),
              const SizedBox(width: 12),
              GuestText(wonText('${totals.total}'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
              const Spacer(),
              if (totals.unpaid != totals.total) ...[
                const GuestText('결제 전', style: TextStyle(fontSize: 16, color: kMuted)),
                const SizedBox(width: 8),
                GuestText(wonText('${totals.unpaid}'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kOrange)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderHistoryEntry entry;
  final String? status; // null = 아직 모름
  final Map<String, Map<String, dynamic>> menus;

  const _OrderCard({required this.entry, required this.status, required this.menus});

  // 메뉴 이름 번역 (83차) — 없으면 주문할 때 이름 그대로
  String _menuName(BuildContext context, OrderHistoryLine l) {
    final m = menus[l.menuId];
    return m == null ? l.name : guestField(context, {...m, 'name': m['name'] ?? l.name}, 'name');
  }

  String _optionName(BuildContext context, OrderHistoryLine l, String option) {
    final groups = menus[l.menuId]?['optionGroups'];
    if (groups is List) {
      for (final g in groups) {
        final opts = g is Map ? g['options'] : null;
        if (opts is! List) continue;
        for (final o in opts) {
          if (o is Map && o['name']?.toString() == option) return guestField(context, o, 'name');
        }
      }
    }
    return option;
  }

  @override
  Widget build(BuildContext context) {
    final dim = entry.cancelled;
    final ink = dim ? kMuted : kInk;
    final rows = <Widget>[];
    if (entry.lines.isNotEmpty) {
      for (final l in entry.lines) {
        final opts = l.options.map((o) => _optionName(context, l, o)).join(', ');
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: _menuName(context, l),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink,
                          decoration: dim ? TextDecoration.lineThrough : null),
                    ),
                    if (opts.isNotEmpty)
                      TextSpan(text: '  $opts', style: const TextStyle(fontSize: 15, color: kMuted)),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Text('× ${l.quantity}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ink)),
            ],
          ),
        ));
      }
    } else {
      for (final s in entry.items) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(s, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ink)),
        ));
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      decoration: BoxDecoration(
        color: dim ? const Color(0xFFF7F4EE) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (entry.at != null)
                GuestText(formatTimeKo(entry.at!), style: const TextStyle(fontSize: 15, color: kMuted)),
              const Spacer(),
              if (entry.cancelled)
                const _Chip(text: '취소됨', color: kMuted)
              else ...[
                if (status != null) _Chip(text: orderHistoryStatusText(status), color: _statusColor(status!)),
                if (entry.paid) ...[
                  const SizedBox(width: 8),
                  const _Chip(text: '결제됨', color: kBlue, filled: true),
                ],
              ],
            ],
          ),
          const SizedBox(height: 12),
          ...rows,
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: GuestText(
              wonText('${entry.price}'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink,
                  decoration: dim ? TextDecoration.lineThrough : null),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'pending' => kBody,
        'preparing' => kAmber,
        'ready' => kOrange,
        _ => const Color(0xFF3F8F5A),
      };
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  const _Chip({required this.text, required this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: GuestText(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: filled ? Colors.white : color),
      ),
    );
  }
}
