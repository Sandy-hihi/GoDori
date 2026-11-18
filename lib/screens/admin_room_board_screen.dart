import 'dart:async';

import 'package:flutter/material.dart';
import 'package:boardpad/models/order_history.dart';
import 'package:boardpad/models/room_board.dart';
import 'package:boardpad/services/room_settings_service.dart';
import 'package:boardpad/services/store_features.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/toss_pos_service.dart';
import 'package:boardpad/services/usage_meter.dart';
import 'package:boardpad/widgets/admin_busy_dialog.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/admin_dialog_width.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';

/// 방 현황판 (112차) — 방마다 이용 중·진행 중 주문·직원 호출·결제 대기를 한눈에 (읽기 전용)
/// 계산은 lib/models/room_board.dart. 주문 처리(상태 바꾸기)는 그대로 관리자 패드 '주문현황'에서.
///  - 관리자 웹: 왼쪽 메뉴 '방 현황판' (사이드바가 직접 엶 — admin_sidebar.dart)
///  - 관리자 패드: 주문현황 위 [방 현황판] 버튼 → pad: true (사이드바 없이 뒤로 가기)
class AdminRoomBoardScreen extends StatefulWidget {
  final bool pad;
  const AdminRoomBoardScreen({super.key, this.pad = false});

  @override
  State<AdminRoomBoardScreen> createState() => _AdminRoomBoardScreenState();
}

class _AdminRoomBoardScreenState extends State<AdminRoomBoardScreen> {
  static const _orange = Color(0xFFE67E22);
  // 114차 2: 단체손님 묶음 테두리 색 (토스처럼 묶인 방을 같은 색으로) — 결제 대기 주황·호출 빨강과 겹치지 않게
  static const _groupColors = [Color(0xFFD6457A), Color(0xFF7B5CD6), Color(0xFF12908E), Color(0xFF2F6FD6), Color(0xFF8D6E3F)];

  // 구독은 화면을 열 때 한 번만 (100차 규칙)
  final List<StreamSubscription> _subs = [];
  Timer? _tick; // '40분째' 같은 시간 글자를 30초마다 다시
  Map<String, Map<String, dynamic>> _roomStatus = {};
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _calls = [];
  int? _roomCount;
  bool _tossPos = false;
  bool _statusLoaded = false, _ordersLoaded = false, _callsLoaded = false;
  String? _error;
  RoomBoardState? _filter; // null = 전체

  @override
  void initState() {
    super.initState();
    void fail(Object e) {
      if (mounted) setState(() => _error = '불러오지 못했어요: $e');
    }

    _subs.add(StoreScope.col('roomStatus').snapshots().metered().listen((s) {
      if (!mounted) return;
      setState(() {
        _roomStatus = {for (final d in s.docs) d.id: d.data()};
        _statusLoaded = true;
      });
    }, onError: fail));
    _subs.add(StoreScope.col('orders')
        .where('status', whereIn: const ['pending', 'preparing', 'ready'])
        .snapshots()
        .metered()
        .listen((s) {
      if (!mounted) return;
      setState(() {
        _orders = [for (final d in s.docs) {...d.data(), 'id': d.id}];
        _ordersLoaded = true;
      });
    }, onError: fail));
    _subs.add(StoreScope.col('staff_calls').where('isAcknowledged', isEqualTo: false).snapshots().metered().listen((s) {
      if (!mounted) return;
      setState(() {
        _calls = [for (final d in s.docs) d.data()];
        _callsLoaded = true;
      });
    }, onError: fail));
    _subs.add(RoomSettingsService.watchCount().listen((n) {
      if (mounted) setState(() => _roomCount = n);
    }));
    _subs.add(StoreFeaturesService.watch().listen((f) {
      if (mounted) setState(() => _tossPos = f.tossPos);
    }));
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _tick?.cancel();
    super.dispose();
  }

  bool get _loaded => _statusLoaded && _ordersLoaded && _callsLoaded && _roomCount != null;

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _won(int v) =>
      '${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

  Color _stateColor(RoomBoardState s) => switch (s) {
        RoomBoardState.awaitingPay => _orange,
        RoomBoardState.inUse => kAdminAccent,
        RoomBoardState.empty => Colors.grey.shade400,
      };

  // ───────────────────────── 위 요약 (누르면 그 상태만) ─────────────────────────
  Widget _filterChip(String label, int count, RoomBoardState? value, Color color) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text('$label  $count', style: TextStyle(fontWeight: FontWeight.bold, color: selected ? Colors.white : color)),
      selected: selected,
      showCheckmark: false,
      selectedColor: color,
      backgroundColor: Colors.white,
      side: BorderSide(color: color.withValues(alpha: 0.6)),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _header(List<RoomBoardEntry> board, bool narrow) {
    int count(RoomBoardState s) => board.where((e) => e.state == s).length;
    final orders = board.fold<int>(0, (t, e) => t + e.orders.length);
    final calls = board.fold<int>(0, (t, e) => t + e.calls.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.pad) ...[
          Text('방 현황판', style: TextStyle(fontSize: narrow ? 24 : 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('실시간으로 바뀌어요. 방을 누르면 주문 내용을 볼 수 있어요. (주문 처리는 관리자 패드 주문현황에서)',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _filterChip('전체', board.length, null, kAdminAccent),
            _filterChip('이용 중', count(RoomBoardState.inUse), RoomBoardState.inUse, kAdminAccent),
            _filterChip('결제 대기', count(RoomBoardState.awaitingPay), RoomBoardState.awaitingPay, _orange),
            _filterChip('비어 있음', count(RoomBoardState.empty), RoomBoardState.empty, Colors.grey.shade600),
            const SizedBox(width: 8),
            Text('진행 중 주문 $orders건 · 확인 안 한 호출 $calls건',
                style: TextStyle(color: calls > 0 ? Colors.redAccent : Colors.black54, fontWeight: FontWeight.w600)),
          ],
        ),
        if (!_tossPos)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: kAdminAccentSoft, borderRadius: BorderRadius.circular(8)),
            child: const Text(
              '토스 POS 연동을 켠 매장만 결제 대기·이번 손님 주문 합계가 보여요. 지금은 진행 중 주문과 직원 호출로 이용 중을 표시해요.',
              style: TextStyle(color: kAdminAccent, fontSize: 13),
            ),
          ),
      ],
    );
  }

  // ───────────────────────── 방 카드 ─────────────────────────
  Widget _line(IconData icon, String text, {Color color = Colors.black87, FontWeight weight = FontWeight.normal}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 13, fontWeight: weight)),
            ),
          ],
        ),
      );

  Widget _roomCard(RoomBoardEntry e, DateTime now, [Color? groupColor]) {
    final card = _roomCardInner(e, now, groupColor);
    if (groupColor == null) return card;
    // 114차 2: 단체손님 — 카드 바깥을 묶음 색으로 한 번 더 감쌈
    return Tooltip(
      message: '포스 단체손님 묶음 · ${e.group!.rooms.map((r) => '$r번').join(', ')} 방',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: groupColor, width: 3),
        ),
        child: card,
      ),
    );
  }

  Widget _roomCardInner(RoomBoardEntry e, DateTime now, Color? groupColor) {
    final color = _stateColor(e.state);
    final empty = e.state == RoomBoardState.empty;
    final orderParts = [
      if (e.countOf('pending') > 0) '접수 ${e.countOf('pending')}',
      if (e.countOf('preparing') > 0) '준비 중 ${e.countOf('preparing')}',
      if (e.countOf('ready') > 0) '준비 완료 ${e.countOf('ready')}',
    ];
    final callReasons = {for (final c in e.calls) c.label}.join(', ');
    final settledToday = e.settledAt != null &&
        e.settledAt!.year == now.year &&
        e.settledAt!.month == now.month &&
        e.settledAt!.day == now.day;
    return Material(
      color: empty ? const Color(0xFFFAFAFA) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetail(e),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: e.calls.isNotEmpty ? Colors.redAccent : color.withValues(alpha: empty ? 0.5 : 1),
              width: empty ? 1 : 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('${e.room}',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: empty ? Colors.black38 : Colors.black87)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('번 방', style: TextStyle(color: empty ? Colors.black38 : Colors.black54)),
                  ),
                  const Spacer(),
                  if (groupColor != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: groupColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('단체',
                          style: TextStyle(color: groupColor, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: empty ? Colors.grey.shade200 : color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(e.stateLabel,
                        style: TextStyle(
                            color: empty ? Colors.black54 : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              if (e.beyondCount)
                const Text('방 개수 밖', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
              if (e.calls.isNotEmpty)
                _line(Icons.notifications_active, '호출 ${e.calls.length} · $callReasons',
                    color: Colors.redAccent, weight: FontWeight.bold),
              if (orderParts.isNotEmpty)
                _line(Icons.receipt_long_outlined, '주문 ${orderParts.join(' · ')}',
                    color: e.countOf('pending') > 0 ? _orange : kAdminAccent, weight: FontWeight.w600)
              else if (!empty)
                _line(Icons.receipt_long_outlined, '진행 중 주문 없음', color: Colors.black45),
              if (e.posPayment != null)
                _line(Icons.payments_outlined,
                    '일부 결제 ${_won(e.posPayment!.paid)} · 남은 ${_won(e.posPayment!.unpaid)} (포스)',
                    color: _orange, weight: FontWeight.bold)
              // 114차: 모두 취소된 방이 '합계 0원 · 결제됨'으로 보이던 것
              else if (e.allCancelled)
                _line(Icons.payments_outlined, '주문 ${e.cycle.length}건 모두 취소됨', color: Colors.black45)
              else if (e.cycle.isNotEmpty)
                _line(Icons.payments_outlined,
                    e.unpaid > 0 ? '결제 전 ${_won(e.unpaid)} / 합계 ${_won(e.total)}' : '합계 ${_won(e.total)} · 결제됨',
                    color: e.unpaid > 0 ? _orange : Colors.black54, weight: e.unpaid > 0 ? FontWeight.bold : FontWeight.normal),
              // 117차: 포스 계산서(직원이 포스에서 직접 넣은 메뉴 포함)
              if (e.posBill != null)
                _line(Icons.receipt_long_outlined,
                    '포스 계산서 ${_won(e.posBill!.total)}${e.posExtra > 0 ? ' · 포스 추가 ${_won(e.posExtra)}' : ''}',
                    color: e.posBill!.unpaid > 0 ? _orange : Colors.black54, weight: FontWeight.w600),
              const Spacer(),
              if (e.firstAt != null && !empty)
                Text('첫 주문 ${_hm(e.firstAt!)} · ${roomElapsedLabel(e.firstAt!, now)}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12))
              // 114차: 포스 자리이동·합석으로 옮겨 간 방
              else if (empty && settledToday && e.movedTo != null)
                Text('${_hm(e.settledAt!)} ${e.movedTo}번 방으로 옮김', style: const TextStyle(color: Colors.black45, fontSize: 12))
              else if (empty && settledToday)
                Text('마지막 정산 ${_hm(e.settledAt!)}', style: const TextStyle(color: Colors.black38, fontSize: 12))
              else if (empty)
                const Text('—', style: TextStyle(color: Colors.black26, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── 방 누르면: 자세히 ─────────────────────────
  void _showDetail(RoomBoardEntry e) {
    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        );
    String cycleText(OrderHistoryEntry c) => c.lines.isNotEmpty
        ? c.lines
            .map((l) => '${l.name}${l.options.isEmpty ? '' : '(${l.options.join(', ')})'} x ${l.quantity}')
            .join(', ')
        : c.items.join(', ');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${e.room}번 방 · ${e.stateLabel}${e.group == null ? '' : ' · 단체 ${e.group!.rooms.join('·')}번'}', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: adminDialogWidth(ctx, 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (e.calls.isNotEmpty) ...[
                  title('확인 안 한 직원 호출'),
                  for (final c in e.calls)
                    Text('• ${c.at == null ? '' : '${_hm(c.at!)}  '}${c.label}', style: const TextStyle(color: Colors.redAccent)),
                ],
                // 117차
                if (e.posBill != null) ...[
                  title('포스 계산서'),
                  Text('합계 ${_won(e.posBill!.total)} · 결제 전 ${_won(e.posBill!.unpaid)}'
                      '${e.posBill!.paid > 0 ? ' · 결제됨 ${_won(e.posBill!.paid)}' : ''}'),
                  if (e.posExtra > 0)
                    Text('패드 주문보다 ${_won(e.posExtra)} 많아요 — 직원이 포스에서 직접 넣은 메뉴',
                        style: const TextStyle(color: Colors.black54, fontSize: 13)),
                ],
                title('진행 중 주문'),
                if (e.orders.isEmpty)
                  const Text('없어요', style: TextStyle(color: Colors.black45))
                else
                  for (final o in e.orders)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${o.at == null ? '' : '${_hm(o.at!)}  '}[${o.statusLabel}]  ${o.items.join(', ')}'
                        '${o.price > 0 ? '  (${_won(o.price)})' : ''}',
                      ),
                    ),
                if (e.cycle.isNotEmpty) ...[
                  title('이번 손님 주문 (포스)'),
                  for (final c in e.cycle)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${c.at == null ? '' : '${_hm(c.at!)}  '}${cycleText(c)}  ${_won(c.price)}'
                        '  ${c.cancelled ? '· 취소됨' : c.paid ? '· 결제됨' : '· 결제 전'}',
                        style: TextStyle(
                          color: c.cancelled ? Colors.black38 : (c.paid ? Colors.black54 : _orange),
                          decoration: c.cancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  const Divider(height: 20),
                  Text('합계 ${_won(e.total)} · 결제 전 ${_won(e.unpaid)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (e.posPayment != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('포스에서 일부 결제됨 ${_won(e.posPayment!.paid)} · 남은 금액 ${_won(e.posPayment!.unpaid)}',
                          style: const TextStyle(color: _orange, fontSize: 13)),
                    ),
                  if (e.openCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('포스에서 결제를 기다리는 주문 ${e.openCount}건',
                          style: const TextStyle(color: _orange, fontSize: 13)),
                    ),
                ],
                if (e.state == RoomBoardState.empty && e.settledAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                        '마지막 정산 ${e.settledAt!.month}/${e.settledAt!.day} ${_hm(e.settledAt!)}',
                        style: const TextStyle(color: Colors.black54)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          // 115차: 운영자 페이지에만 있던 '방 결제 대기 비우기'를 관리자도 → 116차 '방 비우기'(손님이 나간 방 정리)
          //   결제 대기·주문 내역 + 진행 중 주문은 완료로 + 확인 안 한 호출은 확인으로 + 그 방 패드 처음 화면
          if (e.state != RoomBoardState.empty)
            TextButton(
              onPressed: () async {
                final parts = [
                  if (e.openCount > 0) '결제 대기 ${e.openCount}건',
                  if (e.orders.isNotEmpty) '진행 중 주문 ${e.orders.length}건 → 완료',
                  if (e.calls.isNotEmpty) '직원 호출 ${e.calls.length}건 → 확인',
                ];
                final ok = await showBusyConfirm(
                  ctx,
                  title: '${e.room}번 방 비우기',
                  message: '손님이 나간 방을 정리해요.\n'
                      '${parts.isEmpty ? '' : '${parts.join(' · ')}\n'}'
                      '주문 내역을 비우고, 그 방 손님 패드는 처음 화면(기본 언어)으로 돌아가요.\n'
                      '포스 주문은 바뀌지 않아요.',
                  confirmLabel: '비우기',
                  errorText: '비우지 못했어요',
                  action: () => TossPosService.clearRoom(e.room),
                );
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('방 비우기'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }

  Widget _body(bool narrow) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final now = DateTime.now();
    final board = buildRoomBoard(roomCount: _roomCount!, roomStatus: _roomStatus, orders: _orders, calls: _calls);
    final shown = _filter == null ? board : board.where((e) => e.state == _filter).toList();
    final groupIndex = roomGroupColorIndex(board);
    Color? groupColor(RoomBoardEntry e) =>
        e.group == null
            ? null
            : e.group!.color != null
                ? Color(e.group!.color!) // 115차: 토스에서 고른 묶음 색 그대로
                : _groupColors[groupIndex[e.group!.id]! % _groupColors.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(board, narrow),
        const SizedBox(height: 16),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('해당하는 방이 없어요.', style: TextStyle(color: Colors.black45)))
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisExtent: 196,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _roomCard(shown[i], now, groupColor(shown[i])),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    if (widget.pad) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        appBar: AppBar(
          backgroundColor: kAdminAccent,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('방 현황판', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: Padding(padding: const EdgeInsets.all(16), child: _body(narrow)),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Row(
        children: [
          AdminSidebar(currentScreen: 'rooms', onNavigate: (s) => AdminSidebar.go(context, s)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(narrow ? 16.0 : 32.0),
              child: _body(narrow),
            ),
          ),
        ],
      ),
    );
  }
}

