import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/models/home_extra.dart';
import 'package:boardpad/models/order_flow.dart';
import 'package:boardpad/models/order_history.dart';
import 'package:boardpad/screens/game_list_screen.dart';
import 'package:boardpad/screens/game_tools_screen.dart';
import 'package:boardpad/services/game_catalog.dart';
import 'package:boardpad/services/store_features.dart';
import 'package:boardpad/services/store_info_service.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/usage_meter.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/widgets/home_common.dart';
import 'home_theme.dart';

/// 134차: 홈 격자 위젯 7개 (사장님이 홈 꾸미기에서 넣고 뺌)
///   foodStatus 내 음식 상태 · orderSummary 주문 내역 · language 언어 바꾸기 · fingerTools 팀 나누기·선 뽑기
///   randomGame 랜덤 게임 뽑기 · newGames 새로 들어온 게임 · storeHours 매장 전화번호·영업시간
/// 계산은 models/home_extra.dart. 손님에게 보이는 고정 문구는 GuestText(guest_messages.dart).
/// preview = 관리자 홈 꾸미기 미리보기 — 방 주문 같은 패드 데이터는 읽지 않고 예시로 보여 줌.

const _green = Color(0xFF2E9E5B);
const _greenBg = Color(0xFFE6F4EC);

/// 미리보기 전용 안내 카드 (손님 화면엔 안 나옴 — 관리자 화면이라 한국어만)
class _PreviewNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PreviewNote(this.icon, this.text);

  @override
  Widget build(BuildContext context) => HomeCard(
        color: const Color(0xFFFFF8EC),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFFB5751E), size: 28),
              const SizedBox(height: 8),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF8A7F70), height: 1.4)),
            ],
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════
// 1. 내 음식 상태 — 이 방의 진행 중 주문(접수·준비 중·준비 완료)
// ═══════════════════════════════════════════════════════════

/// 메뉴 이름 번역용 — 매장별로 한 번 읽고 1시간 동안 씀 (주문이 있을 때만 읽음)
class _MenuNames {
  static String? _store;
  static DateTime? _at;
  static Future<Map<String, Map<String, dynamic>>>? _future;

  static Future<Map<String, Map<String, dynamic>>> load() {
    if (!StoreScope.isSet) return Future.value(const {});
    final at = _at;
    if (_store != StoreScope.id || at == null || DateTime.now().difference(at) > const Duration(hours: 1)) {
      _store = StoreScope.id;
      _at = DateTime.now();
      _future = StoreScope.col('menus').get().metered().then(
            (s) => {for (final d in s.docs) d.id: d.data()},
            onError: (_) {
              _at = null; // 다음에 다시
              return <String, Map<String, dynamic>>{};
            },
          );
    }
    return _future!;
  }
}

class FoodStatusWidget extends StatefulWidget {
  final int? roomNumber;
  final int w, h;
  final bool preview;
  const FoodStatusWidget({super.key, this.roomNumber, required this.w, required this.h, this.preview = false});

  @override
  State<FoodStatusWidget> createState() => _FoodStatusWidgetState();
}

class _FoodStatusWidgetState extends State<FoodStatusWidget> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _orders;
  Map<String, Map<String, dynamic>> _menus = const {};
  bool _menusAsked = false;

  @override
  void initState() {
    super.initState();
    if (!widget.preview && StoreScope.isSet) {
      _orders = StoreScope.col('orders')
          .where('room', isEqualTo: '#${widget.roomNumber ?? 1}') // 보안 규칙: 패드는 자기 방 주문만
          .where('status', whereIn: const ['pending', 'preparing', 'ready'])
          .snapshots()
          .metered();
    }
  }

  void _askMenus() {
    if (_menusAsked) return;
    _menusAsked = true;
    _MenuNames.load().then((m) {
      if (mounted) setState(() => _menus = m);
    });
  }

  /// 주문 → (첫 메뉴 이름(번역), 나머지 개수)
  ({String first, int more}) _names(BuildContext context, Map<String, dynamic> order) {
    final names = <String>[];
    final lines = order['lines'];
    if (lines is List) {
      for (final l in lines.whereType<Map>()) {
        final name = (l['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final m = _menus[(l['menuId'] ?? '').toString()];
        names.add(m == null ? name : guestField(context, {...m, 'name': m['name'] ?? name}, 'name'));
      }
    }
    if (names.isEmpty && order['items'] is List) {
      for (final s in (order['items'] as List)) {
        names.add(s.toString().replaceAll(RegExp(r'\s*x\s*\d+$'), ''));
      }
    }
    if (names.isEmpty) return (first: '', more: 0);
    return (first: names.first, more: names.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preview) {
      return _frame(context, [
        _Row(first: '아메리카노', more: 1, status: 'preparing', flow: OrderFlow.serve, time: null),
        _Row(first: '감자튀김', more: 0, status: 'pending', flow: OrderFlow.serve, time: null),
      ]);
    }
    final stream = _orders;
    if (stream == null) return _frame(context, const []);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final docs = [...?snap.data?.docs];
        if (docs.isNotEmpty) _askMenus();
        int ms(QueryDocumentSnapshot<Map<String, dynamic>> d) {
          final t = d.data()['timestamp'];
          return t is Timestamp ? t.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch;
        }

        docs.sort((a, b) => ms(a).compareTo(ms(b)));
        final rows = [
          for (final d in docs)
            () {
              final data = d.data();
              final n = _names(context, data);
              final t = data['timestamp'];
              return _Row(
                first: n.first,
                more: n.more,
                status: (data['status'] ?? 'pending').toString(),
                flow: OrderFlow.parse(data['flow']),
                time: t is Timestamp ? t.toDate() : null,
              );
            }(),
        ];
        return _frame(context, rows);
      },
    );
  }

  Widget _frame(BuildContext context, List<_Row> rows) {
    void open() => openHomeTarget(context, 'food', widget.roomNumber);
    // 1×1: 건수 + 가장 앞선 상태
    if (widget.w == 1) {
      final best = rows.isEmpty ? null : rows.reduce((a, b) => _rank(b.status) > _rank(a.status) ? b : a);
      return HomeCard(
        color: rows.isEmpty ? Colors.white : kCreamCard,
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.room_service_outlined, color: kOrange, size: 26),
            if (best == null)
              const GuestText('주문한 음식이 없어요',
                  maxLines: 2, style: TextStyle(fontSize: 14, color: kMuted, height: 1.35))
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GuestText('주문 ${rows.length}건', style: const TextStyle(fontSize: 13, color: kMuted)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: GuestText(orderHistoryStatusText(best.status),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _statusColor(best.status))),
                  ),
                ],
              ),
          ],
        ),
      );
    }
    return HomeCard(
      onTap: rows.isEmpty ? open : null,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.room_service_outlined, color: kOrange, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: GuestText('주문한 음식',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
              ),
              if (rows.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: kOrange, borderRadius: BorderRadius.circular(10)),
                  child: Text('${rows.length}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const GuestText('주문한 음식이 없어요', style: TextStyle(fontSize: 14, color: kMuted)),
                        const SizedBox(height: 10),
                        Material(
                          color: kOrange,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: open,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: GuestText('음식 주문하기',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(builder: (context, c) {
                    const rowH = 66.0;
                    final fit = max(1, ((c.maxHeight + 8) / (rowH + 8)).floor());
                    final shown = rows.length > fit ? rows.take(fit - 1 < 1 ? 1 : fit - 1).toList() : rows;
                    final hidden = rows.length - shown.length;
                    return Column(
                      children: [
                        for (final r in shown) ...[
                          SizedBox(height: rowH, child: _OrderRow(row: r)),
                          const SizedBox(height: 8),
                        ],
                        if (hidden > 0)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: GuestText('외 $hidden개', style: const TextStyle(fontSize: 13, color: kMuted)),
                          ),
                      ],
                    );
                  }),
          ),
        ],
      ),
    );
  }
}

int _rank(String s) => switch (s) { 'ready' => 2, 'preparing' => 1, _ => 0 };

Color _statusColor(String s) => switch (s) { 'ready' => _green, 'preparing' => kOrange, _ => kBlue };

class _Row {
  final String first;
  final int more;
  final String status;
  final OrderFlow flow;
  final DateTime? time;
  const _Row({required this.first, required this.more, required this.status, required this.flow, required this.time});
}

class _OrderRow extends StatelessWidget {
  final _Row row;
  const _OrderRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final step = foodOrderStep(row.status, row.flow);
    final color = _statusColor(row.status);
    final readyHint = row.status == 'ready' && row.flow.isPickup
        ? (row.flow.payAtPickup ? '카운터에서 결제하고 받아 가세요' : '카운터에서 받아 가세요')
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: row.status == 'ready' ? _greenBg : kBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(row.first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
                    ),
                    if (row.more > 0) ...[
                      const SizedBox(width: 4),
                      GuestText('외 ${row.more}개', style: const TextStyle(fontSize: 13, color: kMuted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                flex: 2,
                child: GuestText(readyHint ?? orderHistoryStatusText(row.status),
                    maxLines: 1,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
          // 단계 막대 (접수 · 준비 중 · 준비 완료/자리로 전달)
          Row(
            children: [
              for (var i = 0; i < step.steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        height: 5,
                        decoration: BoxDecoration(
                          color: i <= step.index ? color : kLine,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 3),
                      GuestText(step.steps[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: i == step.index ? FontWeight.w800 : FontWeight.w500,
                              color: i <= step.index ? kInk : kMuted)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 2. 주문 내역 — 이 방 주문 합계 (토스 POS 연동 매장만)
// ═══════════════════════════════════════════════════════════

class OrderSummaryWidget extends StatefulWidget {
  final int? roomNumber;
  final int w, h;
  final bool preview;
  const OrderSummaryWidget({super.key, this.roomNumber, required this.w, required this.h, this.preview = false});

  @override
  State<OrderSummaryWidget> createState() => _OrderSummaryWidgetState();
}

class _OrderSummaryWidgetState extends State<OrderSummaryWidget> {
  late final Stream<StoreFeatures>? _features = StoreScope.isSet ? StoreFeaturesService.watch() : null;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _room = (!widget.preview && StoreScope.isSet)
      ? StoreScope.col('roomStatus').doc('${widget.roomNumber ?? 1}').snapshots()
      : null;

  @override
  Widget build(BuildContext context) {
    final f = _features;
    if (f == null) return const SizedBox.shrink();
    return StreamBuilder<StoreFeatures>(
      stream: f,
      initialData: StoreFeaturesService.last,
      builder: (context, fs) {
        final toss = fs.data?.tossPos == true;
        if (!toss) {
          return widget.preview
              ? const _PreviewNote(Icons.receipt_long_outlined, '토스 POS 연동 매장에서만\n손님 화면에 보여요')
              : const SizedBox.shrink();
        }
        if (widget.preview) return _body(context, count: 2, total: 12500, unpaid: 12500);
        final room = _room;
        if (room == null) return const SizedBox.shrink();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: room,
          builder: (context, r) {
            final list = OrderHistoryEntry.listFrom(r.data?.data()).where((e) => !e.cancelled).toList();
            final t = orderHistoryTotals(list);
            return _body(context, count: list.length, total: t.total, unpaid: t.unpaid);
          },
        );
      },
    );
  }

  Widget _body(BuildContext context, {required int count, required int total, required int unpaid}) {
    void open() => openHomeTarget(context, 'orders', widget.roomNumber);
    final amount = unpaid > 0 ? unpaid : total;
    final amountLabel = unpaid > 0 ? '결제 전' : '주문 합계';
    if (widget.h == 1) {
      return HomeCard(
        onTap: open,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, color: kInk, size: 22),
            const SizedBox(width: 10),
            const GuestText('주문 내역', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
            const Spacer(),
            if (count > 0)
              GuestText(wonText('$amount'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kOrange)),
            const Icon(Icons.chevron_right, color: kMuted),
          ],
        ),
      );
    }
    return HomeCard(
      onTap: open,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HomeCardHeader(icon: Icons.receipt_long_outlined, iconColor: kInk, title: '주문 내역'),
          const Spacer(),
          if (count == 0)
            const GuestText('아직 주문이 없어요', style: TextStyle(fontSize: 15, color: kMuted))
          else ...[
            Row(
              children: [
                GuestText('주문 $count건', style: const TextStyle(fontSize: 13, color: kMuted)),
                const SizedBox(width: 6),
                Flexible(
                  child: GuestText(amountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: unpaid > 0 ? kOrange : _green)),
                ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: GuestText(wonText('$amount'),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kInk)),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 3. 언어 바꾸기 — 한국어·English·中文·日本語 큰 버튼
// ═══════════════════════════════════════════════════════════

class LanguageWidget extends StatelessWidget {
  final int w, h;
  const LanguageWidget({super.key, required this.w, required this.h});

  static const _sub = ['Korean', 'English', 'Chinese', 'Japanese'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GuestLanguage.instance,
      builder: (context, _) {
        final current = GuestLanguage.instance.code;
        final names = GuestLanguage.names;
        // 1×1: 지금 언어 + 누르면 고르기 창
        if (w == 1) {
          return HomeCard(
            onTap: () => showGuestLanguagePicker(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: kOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.translate_rounded, color: kOrange, size: 22),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Language · 言語', style: TextStyle(fontSize: 11, color: kMuted)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(names[GuestLanguage.codes.indexOf(current)],
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
        Widget button(int i, {bool compact = false}) {
          final selected = GuestLanguage.codes[i] == current;
          return Material(
            color: selected ? kOrange : kBg,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => GuestLanguage.instance.select(GuestLanguage.codes[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(names[i],
                            style: TextStyle(
                                fontSize: compact ? 15 : 18,
                                fontWeight: FontWeight.w800,
                                color: selected ? Colors.white : kInk)),
                      ),
                      if (!compact)
                        Text(_sub[i],
                            style: TextStyle(
                                fontSize: 11, color: selected ? Colors.white.withValues(alpha: 0.85) : kMuted)),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // 2×0.5: 버튼 4개 한 줄
        if (h == 1) {
          return Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: button(i, compact: true)),
                ],
              ],
            ),
          );
        }
        // 2×1: 제목 + 2×2 버튼
        return HomeCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.translate_rounded, color: kOrange, size: 18),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('언어 · Language · 语言 · 言語',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  children: [
                    for (var r = 0; r < 2; r++) ...[
                      if (r > 0) const SizedBox(height: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: button(r * 2)),
                            const SizedBox(width: 8),
                            Expanded(child: button(r * 2 + 1)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 4. 팀 나누기·선 뽑기 바로가기 (게임도구 손가락 화면)
// ═══════════════════════════════════════════════════════════

class FingerToolsWidget extends StatelessWidget {
  final int? roomNumber;
  final int w, h;
  final String mode; // 'both' | 'team' | 'pick'
  const FingerToolsWidget({super.key, this.roomNumber, required this.w, required this.h, this.mode = 'both'});

  void _open(BuildContext context, bool pick) =>
      homeGo(context, GameToolsScreen(roomNumber: roomNumber, initialTab: 2, pickFirst: pick));

  @override
  Widget build(BuildContext context) {
    if (h == 1) {
      return Row(
        children: [
          if (mode != 'pick')
            Expanded(
              child: HomePillButton(icon: Icons.group, iconColor: kBlue, label: '팀 나누기', onTap: () => _open(context, false)),
            ),
          if (mode == 'both') const SizedBox(width: 12),
          if (mode != 'team')
            Expanded(
              child: HomePillButton(
                  icon: Icons.touch_app, iconColor: kOrange, label: '선 뽑기', onTap: () => _open(context, true)),
            ),
        ],
      );
    }
    if (w >= 2 && mode == 'both') {
      return Row(
        children: [
          Expanded(child: _panel(context, pick: false)),
          const SizedBox(width: 12),
          Expanded(child: _panel(context, pick: true)),
        ],
      );
    }
    return _panel(context, pick: mode == 'pick');
  }

  Widget _panel(BuildContext context, {required bool pick}) {
    final bg = pick ? const Color(0xFFFFF1E4) : const Color(0xFFE9F0FB);
    final fg = pick ? kOrange : kBlue;
    return HomeCard(
      color: bg,
      onTap: () => _open(context, pick),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(height: 44, child: _Dots(pick: pick)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: GuestText(pick ? '선 뽑기' : '팀 나누기',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
              ),
              const GuestText('손가락을 대고 기다려요',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: kBody)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 손가락 원 그림 — 팀 나누기: 여러 색 / 선 뽑기: 하나만 주황으로 채움
class _Dots extends StatelessWidget {
  final bool pick;
  const _Dots({required this.pick});

  static const _team = [kOrange, kBlue, _green, Color(0xFF8E44D9)];

  @override
  Widget build(BuildContext context) {
    final colors = pick ? [kMuted, kOrange, kMuted] : [_team[0], _team[1], _team[0], _team[1]];
    return Row(
      children: [
        for (var i = 0; i < colors.length; i++)
          Transform.translate(
            offset: Offset(-8.0 * i, (i.isEven ? 4 : -4).toDouble()),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pick && i != 1 ? Colors.white : colors[i],
                border: Border.all(color: colors[i], width: 3),
                boxShadow: pick && i == 1
                    ? [BoxShadow(color: kOrange.withValues(alpha: 0.45), blurRadius: 10, spreadRadius: 2)]
                    : null,
              ),
              child: pick && i == 1 ? const Icon(Icons.touch_app, size: 16, color: Colors.white) : null,
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 5. 랜덤 게임 뽑기 — 인원 고르고 뽑기 (게임 목록은 GameCatalog — 하루 1번)
// ═══════════════════════════════════════════════════════════

class RandomGameWidget extends StatefulWidget {
  final int? roomNumber;
  final int w, h;
  final bool preview;
  const RandomGameWidget({super.key, this.roomNumber, required this.w, required this.h, this.preview = false});

  @override
  State<RandomGameWidget> createState() => _RandomGameWidgetState();
}

class _RandomGameWidgetState extends State<RandomGameWidget> {
  static const _counts = [2, 3, 4, 5, 6];
  final _rand = Random();
  int? _players;
  Map<String, dynamic>? _picked;
  Map<String, dynamic>? _rollingGame; // 섞는 중에 보여 줄 게임 (이름은 build에서 번역)
  bool _rolling = false;
  bool _empty = false;
  int _gen = 0;

  @override
  void dispose() {
    _gen++;
    super.dispose();
  }

  Future<void> _roll() async {
    if (_rolling || widget.preview) return;
    final gen = ++_gen;
    setState(() {
      _rolling = true;
      _empty = false;
    });
    List<Map<String, dynamic>> games;
    try {
      games = await GameCatalog.load();
    } catch (_) {
      games = const [];
    }
    if (!mounted || gen != _gen) return;
    final pool = randomGameCandidates(games, _players);
    if (pool.isEmpty) {
      setState(() {
        _rolling = false;
        _picked = null;
        _empty = true;
      });
      return;
    }
    // 이름이 빠르게 바뀌다 느려지며 멈춤
    const delays = [45, 45, 50, 55, 60, 70, 80, 95, 115, 140, 175, 220];
    for (final d in delays) {
      if (!mounted || gen != _gen) return;
      final g = pool[_rand.nextInt(pool.length)];
      setState(() => _rollingGame = g);
      HapticFeedback.selectionClick();
      await Future<void>.delayed(Duration(milliseconds: d));
    }
    if (!mounted || gen != _gen) return;
    Map<String, dynamic> pick = pool[_rand.nextInt(pool.length)];
    if (pool.length > 1 && pick['_docId'] == _picked?['_docId']) {
      pick = pool[_rand.nextInt(pool.length)]; // 같은 게임 연달아 덜 나오게
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _picked = pick;
      _rolling = false;
      _rollingGame = null;
    });
  }

  void _openPicked() {
    final id = _picked?['_docId']?.toString();
    if (id == null) return;
    homeGo(context, GameListScreen(roomNumber: widget.roomNumber, initialGameId: id));
  }

  @override
  Widget build(BuildContext context) {
    return HomeCard(
      color: const Color(0xFFF0EBFA),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.shuffle, color: kPurple, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: GuestText('랜덤 게임 뽑기',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF2E2346))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const GuestText('몇 명이서 하세요?', style: TextStyle(fontSize: 12.5, color: Color(0xFF6A5F80))),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < _counts.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _countChip(_counts[i])),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: _result()),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _rolling ? null : _roll,
              style: FilledButton.styleFrom(
                backgroundColor: kPurple,
                disabledBackgroundColor: kPurple.withValues(alpha: 0.45),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.casino, size: 20),
              label: GuestText(_picked == null ? '뽑기' : '다시 뽑기',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(int n) {
    final selected = _players == n;
    return Material(
      color: selected ? kPurple : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _rolling ? null : () => setState(() => _players = selected ? null : n),
        child: SizedBox(
          height: 36,
          child: Center(
            child: Text(n >= 6 ? '6+' : '$n',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: selected ? Colors.white : kInk)),
          ),
        ),
      ),
    );
  }

  Widget _result() {
    final box = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16));
    if (_rolling) {
      final rg = _rollingGame;
      final rollingTitle = rg == null ? '…' : guestField(context, rg, 'title');
      return Container(
        decoration: box,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 60),
          child: Text(rollingTitle,
              key: ValueKey(rollingTitle),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF8D82A6))),
        ),
      );
    }
    final g = _picked;
    if (g == null) {
      return Container(
        decoration: box,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(10),
        child: GuestText(_empty ? '맞는 게임이 없어요' : '인원을 고르고 뽑아 보세요',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: kMuted, height: 1.4)),
      );
    }
    final image = g['imageUrl']?.toString();
    final players = (g['players'] ?? '').toString();
    final time = (g['time'] ?? '').toString();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openPicked,
        child: LayoutBuilder(builder: (context, c) {
          final tall = c.maxHeight >= 190; // 2×2 이상: 사진 위·글 아래
          final pic = ColoredBox(
            color: const Color(0xFFF6F3EE),
            child: hasValidImage(image)
                ? AppNetworkImage(
                    imageUrl: image!,
                    fit: BoxFit.contain,
                    cacheWidth: 360,
                    errorWidget: (c, u, e) => const Icon(Icons.casino_outlined, size: 40, color: kMuted),
                  )
                : const Center(child: Icon(Icons.casino_outlined, size: 40, color: kMuted)),
          );
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(guestField(context, g, 'title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk, height: 1.25)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  if (players.isNotEmpty) GuestText(players, style: const TextStyle(fontSize: 12.5, color: kBody)),
                  if (time.isNotEmpty) GuestText(time, style: const TextStyle(fontSize: 12.5, color: kBody)),
                ],
              ),
            ],
          );
          if (tall) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: pic),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(children: [
                    Expanded(child: info),
                    const Icon(Icons.chevron_right, color: kMuted),
                  ]),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: min(c.maxHeight, c.maxWidth * 0.4), child: pic),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Align(alignment: Alignment.centerLeft, child: info),
                ),
              ),
              const Icon(Icons.chevron_right, color: kMuted),
              const SizedBox(width: 4),
            ],
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 6. 새로 들어온 게임 — NEW 배지 게임(등록 30일 이내) 사진 카드
// ═══════════════════════════════════════════════════════════

class NewGamesWidget extends StatefulWidget {
  final int? roomNumber;
  final bool preview;
  const NewGamesWidget({super.key, this.roomNumber, this.preview = false});

  @override
  State<NewGamesWidget> createState() => _NewGamesWidgetState();
}

class _NewGamesWidgetState extends State<NewGamesWidget> {
  late Future<List<Map<String, dynamic>>> _games = GameCatalog.load();

  @override
  void initState() {
    super.initState();
    GameCatalog.revision.addListener(_reload);
  }

  @override
  void dispose() {
    GameCatalog.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _games = GameCatalog.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _games,
      builder: (context, snap) {
        if (!snap.hasData) return const HomeCard(child: SizedBox.expand());
        final list = newGamesOf(snap.data!);
        if (list.isEmpty) {
          return widget.preview
              ? const _PreviewNote(Icons.inventory_2_outlined, '등록한 지 30일이 안 된 게임(NEW)이\n없으면 손님 화면에선 안 보여요')
              : const SizedBox.shrink();
        }
        return HomeCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => homeGo(context, GameListScreen(roomNumber: widget.roomNumber, initialTab: 'NEW')),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: kBlue, size: 20),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: GuestText('새로 들어온 게임',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(8)),
                      child: const Text('NEW',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    const Spacer(),
                    const GuestText('모두 보기', style: TextStyle(fontSize: 13, color: kMuted)),
                    const Icon(Icons.chevron_right, color: kMuted, size: 20),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  const gap = 10.0;
                  final cols = max(1, ((c.maxWidth + gap) / (130 + gap)).floor());
                  final rows = max(1, ((c.maxHeight + gap) / (150 + gap)).floor());
                  final cellW = (c.maxWidth - gap * (cols - 1)) / cols;
                  final cellH = (c.maxHeight - gap * (rows - 1)) / rows;
                  final shown = list.take(cols * rows).toList();
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final g in shown)
                        SizedBox(width: cellW, height: cellH, child: _NewGameCard(game: g, roomNumber: widget.roomNumber)),
                    ],
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NewGameCard extends StatelessWidget {
  final Map<String, dynamic> game;
  final int? roomNumber;
  const _NewGameCard({required this.game, this.roomNumber});

  @override
  Widget build(BuildContext context) {
    final image = game['imageUrl']?.toString();
    return Material(
      color: kBg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final id = game['_docId']?.toString();
          homeGo(context, GameListScreen(roomNumber: roomNumber, initialGameId: id, initialTab: 'NEW'));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: Colors.white,
                child: hasValidImage(image)
                    ? AppNetworkImage(
                        imageUrl: image!,
                        fit: BoxFit.contain,
                        cacheWidth: 300,
                        errorWidget: (c, u, e) => const Icon(Icons.casino_outlined, size: 32, color: kMuted),
                      )
                    : const Center(child: Icon(Icons.casino_outlined, size: 32, color: kMuted)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
              child: Text(guestField(context, game, 'title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 7. 매장 전화번호·영업시간 — 영업시간은 위젯 설정, 전화번호는 매장 설정(settings/storeInfo)
// ═══════════════════════════════════════════════════════════

class StoreHoursWidget extends StatefulWidget {
  final Map<String, dynamic> options;
  final int w, h;
  final bool preview;
  const StoreHoursWidget({super.key, required this.options, required this.w, required this.h, this.preview = false});

  @override
  State<StoreHoursWidget> createState() => _StoreHoursWidgetState();
}

class _StoreHoursWidgetState extends State<StoreHoursWidget> {
  late final Future<String> _phone = StoreInfoService.phoneNumber();

  @override
  Widget build(BuildContext context) {
    final hours = StoreHours.fromOptions(widget.options);
    return FutureBuilder<String>(
      future: _phone,
      builder: (context, snap) {
        final phone = (snap.data ?? '').trim();
        if (!hours.hasHours && phone.isEmpty) {
          if (!snap.hasData && !widget.preview) return const SizedBox.shrink();
          return widget.preview
              ? const _PreviewNote(Icons.storefront_outlined, '영업시간을 입력해 주세요\n(전화번호는 매장 설정)')
              : const SizedBox.shrink();
        }
        return LiveClock(builder: (context, now) => _body(context, hours, phone, hours.isOpenAt(now)));
      },
    );
  }

  Widget _statusPill(bool? open) {
    if (open == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: open ? _greenBg : kBg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: open ? _green : kMuted, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          GuestText(open ? '지금 영업 중' : '영업시간이 아니에요',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: open ? _green : kMuted)),
        ],
      ),
    );
  }

  /// '휴무 · 월요일, 화요일' 또는 '연중무휴'
  Widget _closedLine(BuildContext context, StoreHours hours, TextStyle style) {
    if (hours.closedDays.isEmpty) return GuestText('연중무휴', style: style);
    final days = hours.closedDays.map((d) => guestTr(context, StoreHours.dayNames[d - 1])).join(', ');
    return Row(
      children: [
        GuestText('휴무', style: style.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Flexible(child: Text(days, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      ],
    );
  }

  Widget _body(BuildContext context, StoreHours hours, String phone, bool? open) {
    const small = TextStyle(fontSize: 12.5, color: kBody);
    final phoneRow = phone.isEmpty
        ? null
        : Row(
            children: [
              const Icon(Icons.call_outlined, size: 16, color: kInk),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(phone, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kInk)),
                ),
              ),
            ],
          );
    if (widget.w == 1) {
      return HomeCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.storefront_outlined, size: 20, color: kOrange),
              const Spacer(),
              if (open != null)
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: open ? _green : kMuted, shape: BoxShape.circle),
                ),
            ]),
            if (hours.hasHours)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const GuestText('영업시간', style: TextStyle(fontSize: 11.5, color: kMuted)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(hours.rangeText,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
                  ),
                ],
              ),
            if (phoneRow != null) phoneRow,
          ],
        ),
      );
    }
    return HomeCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, color: kOrange, size: 20),
              const SizedBox(width: 8),
              const Flexible(
                child: GuestText('영업시간',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
              ),
              const Spacer(),
              _statusPill(open),
            ],
          ),
          const Spacer(),
          if (hours.hasHours) ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(hours.rangeText,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -0.5)),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                if (hours.lastOrder != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const GuestText('라스트 오더', style: TextStyle(fontSize: 12.5, color: kBody, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 5),
                    Text(StoreHours.timeText(hours.lastOrder!), style: small),
                  ]),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: _closedLine(context, hours, small),
                ),
              ],
            ),
          ],
          if (phoneRow != null) ...[
            const Spacer(),
            phoneRow,
          ],
        ],
      ),
    );
  }
}
